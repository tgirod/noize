const std = @import("std");
const testing = std.testing;
const ee = testing.expectEqual;

const node = @import("./node.zig");

/// Identity function
pub fn Id(comptime size: usize) type {
    return struct {
        const Self = @This();
        pub usingnamespace node.NodeInterface(Self);

        pub const in = size;
        pub const out = size;
        pub fn eval(_: *Self, input: [in]f32) [out]f32 {
            return input;
        }
    };
}

test "Id" {
    const N = Id(2);
    try ee(2, N.in);
    try ee(2, N.out);
    var n = N{};
    const output = n.eval(.{ 23, 42 });
    try ee(.{ 23, 42 }, output);
}

/// for testing purpose
pub fn MulAdd(comptime mul: f32, comptime add: f32) type {
    return struct {
        const Self = @This();
        pub usingnamespace node.NodeInterface(Self);

        pub const in = 1;
        pub const out = 1;

        pub fn eval(_: *Self, input: [in]f32) [out]f32 {
            return .{@mulAdd(f32, input[0], mul, add)};
        }
    };
}

test "MulAdd" {
    const N = MulAdd(23, 42);
    var n = N{};
    const output = n.eval(.{1});
    try ee(.{1 * 23 + 42}, output);
}

/// Always return the same values
pub fn Const(comptime args: anytype) type {
    const values: [args.len]f32 = args;

    return struct {
        const Self = @This();
        pub usingnamespace node.NodeInterface(Self);

        pub const in = 0;
        pub const out = values.len;

        pub fn eval(_: *Self, _: [in]f32) [out]f32 {
            return values;
        }
    };
}

test "Const" {
    const N = Const(.{ 1, 2, 3 });
    try ee(3, N.out);
    var n = N{};
    const output = n.eval(.{});
    try ee(.{ 1, 2, 3 }, output);
}

pub fn Range(comptime low: f32, comptime high: f32) type {
    const mul = (high - low) / 2; // target amplitude
    const add = (high + low) / 2; // target midpoint
    return MulAdd(mul, add);
}

/// delay line with a fixed size
pub fn Mem(comptime srate: f32, comptime length: f32) type {
    if (length <= 0) {
        @compileError("length <= 0");
    }

    const size: usize = @intFromFloat(srate * length);

    return struct {
        const Self = @This();
        pub usingnamespace node.NodeInterface(Self);

        pub const in = 1;
        pub const out = 1;

        mem: [size]f32 = [1]f32{0} ** size,
        pos: usize = 0,

        pub fn eval(self: *Self, input: [in]f32) [out]f32 {
            const v = self.mem[self.pos];
            self.mem[self.pos] = input[0];
            self.pos = (self.pos + 1) % size;
            return .{v};
        }
    };
}

test "Mem" {
    const N = Mem(48000, 1.0 / 48000.0);
    var n = N{};
    const input = [_]f32{ 1, 2, 3, 4, 5 };
    const expected = [_]f32{ 0, 1, 2, 3, 4 };
    for (input, expected) |in, exp| {
        const out = n.eval([1]f32{in});
        try ee(exp, out[0]);
    }
}
