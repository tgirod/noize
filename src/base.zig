const std = @import("std");
const testing = std.testing;
const ee = testing.expectEqual;

pub usingnamespace @import("./operators.zig");

// Identity function
fn Id(size: usize) type {
    return struct {
        pub const in = size;
        pub const out = size;
        pub fn eval(_: *@This(), input: [in]f32) [out]f32 {
            return input;
        }
    };
}

test "Id" {
    const N = Id(1);
    var n = N{};
    const output = n.eval(.{23});
    try ee(.{23}, output);
}

// Duplicate inputs
pub fn Fork(comptime N: type) type {
    return struct {
        pub const in = N.in;
        pub const out = N.out * 2;

        n: N = undefined,

        pub inline fn eval(self: *@This(), input: [in]f32) [out]f32 {
            return self.n.eval(input) ** 2;
        }
    };
}

test "Fork" {
    const N = Fork(Id(1));
    try ee(2, N.out);
    var n = N{};
    const output = n.eval(.{23});
    try ee(.{ 23, 23 }, output);
}

// Multiply by and add
pub fn MulAdd(comptime mul: f32, comptime add: f32) type {
    return struct {
        pub const in = 1;
        pub const out = 1;

        pub inline fn eval(_: *@This(), input: [in]f32) [out]f32 {
            return .{@mulAdd(f32, input[0], mul, add)};
        }
    };
}

test "MulAdd" {
    var n = MulAdd(3, 4){};
    const output = n.eval(.{23});
    try ee(.{23 * 3 + 4}, output);
}
