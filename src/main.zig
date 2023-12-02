const std = @import("std");
const n = @import("noize.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allo = gpa.allocator();
    try n.init(allo, 48000, 2, 1);
    defer n.deinit();

    var root = try n.seq(
        n.par(
            n.sin(),
            n.sin(),
        ),
        n.add(),
    );
    defer root.deinit();

    n.in[0] = 100; // freq osc 1
    n.in[1] = 200;

    for (0..480) |index| {
        root.eval(@as(u64, index), n.in, n.out);
        std.debug.print("{any}\n", .{n.out[0]});
    }
}
