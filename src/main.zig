const std = @import("std");
const n = @import("noize.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allo = gpa.allocator();
    try n.init(allo, 48000, 2, 2);
    defer n.deinit();

    var root = try n.par(
        n.sin(),
        n.seq(n.sin(), n.delay(100)),
    );
    defer root.deinit();

    n.in[0] = 100; // freq osc 1
    n.in[1] = 100;

    for (0..480) |index| {
        root.eval(@as(u64, index), n.in, n.out);
        std.debug.print("{any} {any}\n", .{ n.out[0], n.out[1] });
    }
}
