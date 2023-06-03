const std = @import("std");
const termios = std.os.termios;
const mem = std.mem;
const fs = std.fs;
const os = std.os;
const io = std.io;
const File = fs.File;
const BufferedWriter = std.io.BufferedWriter;
const Writer = std.io.Writer;

var orig_termios: termios = undefined;
const Modifier = enum {
    Alt,
    Ctrl,
};
pub const InputContent = union(enum)  {
    escape,
    arrow_up,
    arrow_down,
    arrow_left,
    arrow_right,
    char: u8,
    // add more later
};
const Input = struct {
    mod_alt: bool,
    mod_ctrl: bool,
    content: InputContent,
};

const TuiWriter = struct {
    const Self = @This();
    buf: BufferedWriter(4096, @TypeOf(std.io.getStdOut().writer())),
    pub fn init() Self {
        return Self {
            .buf = io.bufferedWriter(io.getStdOut().writer())
        };
    }
    pub fn flush(self: *Self) !void {
        try self.buf.flush();
    }
    pub fn clear(self: *Self) !void {
        // clear screen
        try self.buf.writer().writeAll("\x1B[2J");
        // bring cursor to upper left corner
        try self.buf.writer().writeAll("\x1B[H");
    }
    pub fn saveScreen(self: *Self) !void {
        try self.buf.writer().writeAll("\x1B[?47h");
    }
    pub fn restoreScreen(self: *Self) !void {
        try self.buf.writer().writeAll("\x1B[?47l");
    }
    pub fn enableAlternateBuffer(self: *Self) !void {
        try self.buf.writer().writeAll("\x1B[?1049h");
    }
    pub fn disableAlternateBuffer(self: *Self) !void {
        try self.buf.writer().writeAll("\x1B[?1049l");
    }
    pub fn hideCursor(self: *Self) !void {
        try self.buf.writer().writeAll("\x1B[?25l");
    }
    pub fn showCursor(self: *Self) !void {
        try self.buf.writer().writeAll("\x1B[?25h");
    }
    pub fn moveCursor(self: *Self, row: usize, col: usize) !void {
        try self.buf.writer().print("\x1B[{};{}H", .{ row + 1, col + 1 });
    }
    pub fn saveCursor(self: *Self) !void {
        try self.buf.writer().writeAll("\x1B[s");
    }
    pub fn restoreCursor(self: *Self) !void {
        try self.buf.writer().writeAll("\x1B[u");
    }
    pub fn charAttributesOff(self: *Self) !void {
        try self.buf.writer().writeAll("\x1Bm");
    }
    pub const CharAttributes = packed struct {
        bold: bool = false,
        lowint: bool = false,
        underline: bool = false,
        reverse: bool = false,
        blink: bool = false,
        invisible: bool = false,
    };
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
