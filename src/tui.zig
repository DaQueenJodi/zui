const std = @import("std");
const termios = std.os.termios;
const mem = std.mem;
const fs = std.fs;
const os = std.os;
const File = fs.File;

var orig_termios: termios = undefined;
const Modifier = enum {
    Alt,
    Ctrl,
};
pub const InputContent = union(enum)  {
    escape: void,
    arrow_up: void,
    arrow_down: void,
    arrow_left: void,
    arrow_right: void,
    char: u8,
    // add more later
};
const Input = struct {
    mod_alt: bool,
    mod_ctrl: bool,
    content: InputContent,
};
pub const TuiCtx = struct {
    orig: termios,
    raw: termios,
    tty: File,

    const Self = @This();
    pub fn init() !Self {
        var tui: TuiCtx = undefined;
        tui.tty = try fs.cwd().openFile("/dev/tty", .{});
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
    pub fn deinit(self: Self) void {
        self.tty.close();
    }

    pub fn start(self: Self) !void {
        try os.tcsetattr(self.tty.handle, .FLUSH, self.raw);
    }
    pub fn stop(self: Self) !void {
        try os.tcsetattr(self.tty.handle, .FLUSH, self.orig);
    }
    pub fn get_input(self: Self) !Input {
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
