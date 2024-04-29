const std = @import("std");

pub fn expectEqualArray(comptime length: usize, expected: [length]f32, actual: [length]f32) !void {
    try std.testing.expectEqualSlices(f32, &expected, &actual);
}

pub const expectOutput = expectEqualArray;
