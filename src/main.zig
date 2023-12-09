const std = @import("std");
const n = @import("noize.zig");

pub fn main() !void {
    const Node = n.Sin();
    var node = Node{};

    for (0..480) |i| {
        const out = node.eval(.{@as(f64, @floatFromInt(i)) * 10});
        std.debug.print("{any}\n", .{out[0]});
    }
}
