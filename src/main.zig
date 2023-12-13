const std = @import("std");
const n = @import("noize.zig");

const step = @as(f32, 1.0 / 48000.0);

pub fn main() !void {
    const Node = n.Sin();
    var node = Node{};

    for (0..480) |i| {
        const out = node.eval(step, .{@as(f64, @floatFromInt(i)) * 10});
        std.debug.print("{any}\n", .{out[0]});
    }
}
