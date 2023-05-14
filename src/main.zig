const std = @import("std");
const tui = @import("tui.zig");
const InputContent = tui.InputContent;
const TuiCtx = tui.TuiCtx;

pub fn main() !void {
    var ctx = try TuiCtx.init();
    defer ctx.deinit();
    try ctx.start();
    while (true) {
        const input = try ctx.get_input();
        switch (input.content) {
            InputContent.char => |c| {
                if (c == 'q') break;
                std.debug.print("got: {c}\r\n", .{c});
            },
            InputContent.escape => {},
            InputContent.arrow_up => {},
            InputContent.arrow_down => {},
            InputContent.arrow_left => {},
            InputContent.arrow_right => {},
        }
        std.debug.print("got: {any}\r\n", .{input});
    }
    try ctx.stop();
}
