const std = @import("std");
const n = @import("noize.zig");

pub fn main() !void {
    var root = n.Noize(
        1,
        [1]n.Tag{.float},
        1,
        [1]n.Tag{.float},
        n.Sin(),
    ){};

    for (0..480) |i| {
        root.input[0].float = @as(f64, @floatFromInt(i)) * 10;
        root.eval();
        std.debug.print("{any}\n", .{root.output[0].float});
    }
}
