const std = @import("std");
const n = @import("noize.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allo = gpa.allocator();
    n.init(allo, 48000);

    const root = try n.seq(
        &n.par(&n.sin(), &n.sin()),
        &n.add(),
    );
    defer root.deinit();

    const input = try allo.alloc(f32, 2);
    const output = try allo.alloc(f32, 1);

    input[0] = 100; // freq
    input[1] = 200;

    for (0..480) |index| {
        root.eval(@as(u64, index), input, output);
        std.debug.print("{any}\n", .{output[0]});
    }
}

const test_allocator = std.testing.allocator;
