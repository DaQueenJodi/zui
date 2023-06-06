const std = @import("std");
const termios = std.os.termios;
const mem = std.mem;
const fs = std.fs;
const os = std.os;
const io = std.io;
const File = fs.File;
const BufferedWriter = std.io.BufferedWriter;
const Writer = std.io.Writer;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

var orig_termios: termios = undefined;
pub const InputContent = union(enum)  {
    escape,
    arrow_up,
    arrow_down,
    arrow_left,
    arrow_right,
    char: u8,
    // add more later
    /// convert string to a key, similar to vim keybinding declarations
    pub fn fromStr(str: []const u8) InputContent {
        const cmp = std.ascii.eqlIgnoreCase;
        if (cmp(str, "<ESC>")) return .escape;
        if (cmp(str, "<LEFT>")) return .arrow_left;
        if (cmp(str, "<RIGHT>")) return .arrow_right;
        if (cmp(str, "<DOWN>")) return .arrow_down;
        if (cmp(str, "<UP>")) return .arrow_up;
        // if its not special, it has to be on char
        assert(str.len == 1);
        return .{ .char = str[0] };
    }
};
pub const Input = struct {
    mod_alt: bool = false,
    mod_ctrl: bool = false,
    content: InputContent,
    fn strIsAlt(str: []const u8) bool {
        const cmp = std.ascii.eqlIgnoreCase;
        if (cmp(str, "ALT")) return true;
        if (cmp(str, "A")) return true;
        if (cmp(str, "M")) return true;
        if (cmp(str, "META")) return true;
        return false;
    }
    fn strIsCtrl(str: []const u8) bool {
        const cmp = std.ascii.eqlIgnoreCase;
        if (cmp(str, "CTRL")) return true;
        if (cmp(str, "C")) return true;
        return false;
    }
    /// converts an input, i.e 'C-r' or 's' or 'C-M-b' to a Input struct that corresponds to it
    /// C-{} -> Ctrl-{}, {A,M}-{} -> Alt-{}
    /// the 
    /// the modifier is NOT case sensitive
    pub fn fromStr(str: []const u8) Input {
        //const toUpper = std.ascii.toUpper;
        assert(str.len > 0);
        var iterator = std.mem.splitBackwardsScalar(u8, str, '-');
        const content = InputContent.fromStr(iterator.next().?);
        var input: Input = undefined;
        input.mod_alt = false;
        input.mod_ctrl = false;
        input.content = content;
        for (0..2) |_| {
            const next = iterator.next();
            if (next == null) break;
            if (strIsAlt(next.?)) {
                assert(input.mod_alt == false);
                input.mod_alt = true;
            } else if (strIsCtrl(next.?)) {
                assert(input.mod_ctrl == false);
                input.mod_ctrl = true;
            }
        }
        return input;
    }
};

test "Input from string" {
    try std.testing.expectEqual(
        Input.fromStr("M-C-w"),
        Input { .mod_ctrl = true, .mod_alt = true, .content = .{ .char = 'w' } }
    );
    try std.testing.expectEqual(
        Input.fromStr("Ctrl-<left>"),
        Input { .mod_ctrl = true, .mod_alt = false, .content = .arrow_left }
    );

}
pub const CharAttributes = packed struct {
    bold: bool = false,
    lowint: bool = false,
    underline: bool = false,
    reverse: bool = false,
    blink: bool = false,
    invisible: bool = false,
};

pub const TuiWriter = struct {
    buff: ArrayList(u8),
    allocator: Allocator,
    const Self = @This();
    pub fn init(allocator: Allocator) Self {
        return Self {
            .buff = ArrayList(u8).init(allocator),
            .allocator = allocator
        };
    }
    pub fn flush(self: *Self) !void {
        std.io.getStdout().writer().writeAll(self.buff.items);
    }
    pub fn clear(self: *Self) !void {
        // clear screen
        self.buff.appendSlice("\x1B[2J");
        // bring cursor to upper left corner
        try self.buff.appendSlice("\x1B[H");
    }
    pub fn saveScreen(self: *Self) !void {
        try self.buff.appendSlice("\x1B[?47h");
    }
    pub fn restoreScreen(self: *Self) !void {
        try self.buff.appendSlice("\x1B[?47l");
    }
    pub fn enableAlternateBuffer(self: *Self) !void {
        try self.buff.appendSlice("\x1B[?1049h");
    }
    pub fn disableAlternateBuffer(self: *Self) !void {
        try self.buff.appendSlice("\x1B[?1049l");
    }
    pub fn hideCursor(self: *Self) !void {
        try self.buff.appendSlice("\x1B[?25l");
    }
    pub fn showCursor(self: *Self) !void {
        try self.buff.appendSlice("\x1B[?25h");
    }
    pub fn moveCursor(self: *Self, row: usize, col: usize) !void {
        try self.buf.writer().print("\x1B[{};{}H", .{ col + 1, row + 1 });
    }
    pub fn saveCursor(self: *Self) !void {
        try self.buff.appendSlice("\x1B[s");
    }
    pub fn restoreCursor(self: *Self) !void {
        try self.buff.appendSlice("\x1B[u");
    }
    pub fn charAttributesOff(self: *Self) !void {
        try self.buff.appendSlice("\x1B[m");
    }
    pub fn charAttributesOn(self: *Self, attrs: CharAttributes) !void {
        var modifier_numbers: [5]u8 = undefined;
        var counter: usize = 0;
        if (attrs.bold) { modifier_numbers[counter] = '1'; counter += 1; }
        if (attrs.lowint) { modifier_numbers[counter] = '2'; counter += 1; }
        if (attrs.underline) { modifier_numbers[counter] = '4'; counter += 1; }
        if (attrs.blink) { modifier_numbers[counter] = '5'; counter += 1; }
        if (attrs.reverse) { modifier_numbers[counter] = '7'; counter += 1; }
        if (attrs.invisible) { modifier_numbers[counter] = '8'; counter += 1; }
        for (modifier_numbers[0..counter]) |char| {
            try self.buf.writer().print("\x1B[{c}m", .{char});
        }
    }
    pub const CharColor = @Vector(3, u8);
    pub fn foregroundColor(self: *Self, color: CharColor) !void {
        try self.buf.writer().print("\x1B[38;2;{};{};{}m", .{color[0], color[1], color[2]});
    }
};

pub const TuiCtx = struct { 
    orig: termios,
    raw: termios,
    tty: File,
    writer: TuiWriter,
    const Self = @This();
    pub fn init() !Self {
        var tui: TuiCtx = undefined;
        tui.tty = try fs.cwd().openFile("/dev/tty", .{});
        tui.writer = TuiWriter.init();
        tui.orig = try os.tcgetattr(tui.tty.handle);
        var raw = tui.orig;
        raw.lflag &= ~@as(
            os.linux.tcflag_t,
            os.linux.ECHO | os.linux.ICANON | os.linux.ISIG | os.linux.IEXTEN,
        );
        raw.iflag &= ~@as(
            os.linux.tcflag_t,
            os.linux.IXON | os.linux.ICRNL | os.linux.BRKINT | os.linux.INPCK | os.linux.ISTRIP,
        );
        raw.cc[os.system.V.TIME] = 0;
        raw.cc[os.system.V.MIN] = 1;
        tui.raw = raw;
        return tui;
    }
    pub fn deinit(self: *Self) void {
        self.tty.close();
    }
    pub fn start(self: *Self) !void {
        try os.tcsetattr(self.tty.handle, .FLUSH, self.raw);
        try self.writer.hideCursor();
        try self.writer.saveCursor();
        try self.writer.saveScreen();
        try self.writer.enableAlternateBuffer();
        try self.writer.flush();
    }
    pub fn stop(self: *Self) !void {
        try os.tcsetattr(self.tty.handle, .FLUSH, self.orig);
        try self.writer.disableAlternateBuffer();
        try self.writer.restoreScreen();
        try self.writer.restoreCursor();
        try self.writer.showCursor();
        try self.writer.flush();
    }
    pub fn get_input(self: *Self) !Input {
        var input: Input = undefined;
        input.mod_alt = false;
        input.mod_ctrl = false;
        var buffer: [1]u8 = undefined;
        _ = try self.tty.read(&buffer);
        if (buffer[0] == '\x1B') {
            var raw = self.raw;
            raw.cc[os.system.V.TIME] = 1;
            raw.cc[os.system.V.MIN] = 0;
            try os.tcsetattr(self.tty.handle, .NOW, raw);
            var esc_buff: [8]u8 = undefined;
            const esc_read = try self.tty.read(&esc_buff);
            try os.tcsetattr(self.tty.handle, .NOW, self.raw);
            if (esc_read == 0) {
                input.content = .escape;
            } else if (mem.eql(u8, esc_buff[0..esc_read], "[A")) {
                input.content = .arrow_up;
            } else if (mem.eql(u8, esc_buff[0..esc_read], "[B")) {
                input.content =  .arrow_down;
            } else if (mem.eql(u8, esc_buff[0..esc_read], "[C")) {
                input.content = .arrow_left;
            } else if (mem.eql(u8, esc_buff[0..esc_read], "[D")) {
                input.content = .arrow_right;
            }
        } else {
            input.content = .{ .char = buffer[0] };
            const chars = "abcdefghijklmnopqrstuvwxyz";
            for (chars) |c| {
                if (buffer[0] == c & '\x1F') {
                    input.mod_ctrl = true;
                    input.content = .{ .char = c };
                    break;
                }
            }
        }
        return input;
    }
};

const TuiChar = packed struct {
    attrs: CharAttributes,
    char: u8,
};
const Point = struct {
    x: usize,
    y: usize,
};
pub const TuiWindow = struct {
    size: Point,
    pos: Point,
    buff: []TuiChar,
    allocator: Allocator,
    const Self = @This();
    pub fn init(allocator: Allocator, pos_x: usize, pos_y: usize, size_x: usize, size_y: usize) !Self {
        var buff = try allocator.alloc(TuiChar, size_x * size_y);
        @memset(buff, .{ .attrs = .{}, .char = ' ' } );
        return Self {
            .pos = .{ .x = pos_x, .y = pos_y },
            .size = .{ .x = size_x, .y = size_y },
            .buff = buff,
            .allocator = allocator
        };
    }
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.buff);
    }
    pub fn coord_to_idx(self: *Self, x: usize, y: usize) usize {
        return x + ( y * self.size.x );
    }
    pub fn printAt(self: *Self, attrs: CharAttributes, x: usize, y: usize, str: []const u8) void {
        var real_y = y;
        var real_x = x;
        for (str) |c| {
            if (c == '\n') {
                real_y += 1;
                if (real_y >= self.size.y) break;
                real_x = 0;
                continue;
            }
            if (real_x >= self.size.x - 1) continue;
            const idx = self.coord_to_idx(real_x, real_y);
            self.buff[idx].char = c;
            self.buff[idx].attrs = attrs;
            real_x += 1;
        }
    }
    pub fn draw(self: *Self, allocator: Allocator, writer: *TuiWriter) !void {
        var lastAttrs: ?CharAttributes = null;
        var buff = ArrayList(u8).init(allocator);
        defer buff.deinit();
        for (0..self.size.y) |y| {
            for (0..self.size.x) |x| {
                try writer.moveCursor(x + self.pos.x, y + self.pos.y);
                const c = self.buff[self.coord_to_idx(x, y)];
                if (lastAttrs == null or !std.meta.eql(lastAttrs.?, c.attrs)) {
                    lastAttrs = c.attrs;
                    try writer.charAttributesOff();
                    try writer.charAttributesOn(c.attrs);
                }
                try buff.append(c.char);
            }
        }
        try writer.buf.writer().writeAll(buff.items);
    }
};

test {
    try std.testing.expect(
        !std.meta.eql(CharAttributes { .bold = true } , CharAttributes {})
    );
}
