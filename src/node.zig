const std = @import("std");
const testing = std.testing;
const ee = testing.expectEqual;

/// for testing purpose
fn Id(comptime size: usize) type {
    return struct {
        const Self = @This();
        pub usingnamespace NodeInterface(Self);

        pub const in = size;
        pub const out = size;
        pub fn eval(_: *Self, input: [in]f32) [out]f32 {
            return input;
        }
    };
}

/// for testing purpose
fn MulAdd(comptime mul: f32, comptime add: f32) type {
    return struct {
        const Self = @This();
        pub usingnamespace NodeInterface(Self);

        pub const in = 1;
        pub const out = 1;

        pub fn eval(_: *Self, input: [in]f32) [out]f32 {
            return .{@mulAdd(f32, input[0], mul, add)};
        }
    };
}

/// Any node should implement this interface. To do so, simply add the following line to your node definition:
/// pub usingnamespace NodeInterface(Self);
/// this will add operator methods to chain nodes in various ways
pub fn NodeInterface(comptime Self: type) type {
    return struct {
        pub fn seq(comptime Next: type) type {
            return Seq(Self, Next);
        }

        pub fn par(comptime Next: type) type {
            return Par(Self, Next);
        }

        pub fn rec(comptime Feedback: type) type {
            return Rec(Self, Feedback);
        }

        pub fn split(comptime Next: type) type {
            return Split(Self, Next);
        }

        pub fn merge(comptime Next: type) type {
            return Merge(Self, Next);
        }
    };
}

/// sequence operator, A --> B
/// if A.out < B.in, spare inputs are added to Seq's inputs
/// if A.out > B.in, spare outputs are added to Seq's outputs
fn Seq(comptime A: type, comptime B: type) type {
    return struct {
        const Self = @This();
        pub usingnamespace NodeInterface(Self);

        pub const in = if (A.out < B.in) A.in + B.in - A.out else A.in;
        pub const out = if (A.out > B.in) B.out + A.out - B.in else B.out;

        a: A = undefined,
        b: B = undefined,

        pub fn eval(self: *Self, input: [in]f32) [out]f32 {
            // spare inputs of B are routed from the main input
            if (A.out < B.in) {
                const input_a = input[0..A.in].*;
                const spare = input[A.in..].*;
                const output_a = self.a.eval(input_a);
                const input_b = output_a ++ spare;
                return self.b.eval(input_b);
            }

            // spare outputs of A are routed to the main output
            if (A.out > B.in) {
                const output_a = self.a.eval(input);
                const input_b = output_a[0..B.in].*;
                const spare = output_a[B.in..].*;
                const output_b = self.b.eval(input_b);
                return output_b ++ spare;
            }

            // no spare input or output
            return self.b.eval(self.a.eval(input));
        }
    };
}

test "seq operator" {
    const PlusOne = MulAdd(1, 1);
    const N = Seq(PlusOne, PlusOne);
    try ee(1, N.in);
    try ee(1, N.out);
    var n = N{};
    const expected = [_]f32{23 + 2};
    const output = n.eval(.{23});
    try ee(expected, output);
}

test "seq operator spare inputs" {
    const N = Seq(Id(1), Id(2));
    try ee(2, N.in);
    try ee(2, N.out);
}

test "seq operator spare outputs" {
    const N = Seq(Id(2), Id(1));
    try ee(2, N.in);
    try ee(2, N.out);
}

/// parallel operator : combine A and B in parallel
fn Par(comptime A: type, comptime B: type) type {
    return struct {
        const Self = @This();
        pub usingnamespace NodeInterface(Self);

        pub const in = A.in + B.in;
        pub const out = A.out + B.out;

        a: A = undefined,
        b: B = undefined,

        pub fn eval(self: *Self, input: [in]f32) [out]f32 {
            return self.a.eval(input[0..A.in].*) ++ self.b.eval(input[A.in..].*);
        }
    };
}

test "par operator" {
    const N = Par(Id(2), Id(3));
    try ee(5, N.in);
    try ee(5, N.out);
    var n = N{};
    const expected = [_]f32{ 1, 2, 3, 4, 5 };
    const output = n.eval(expected);
    try ee(expected, output);
}

/// recursive operator
/// loop A --> B --> A
/// A --> B is delayed one sample to avoid infinite loop
/// spare inputs and outputs of A are Rec's IO
fn Rec(comptime A: type, comptime B: type) type {
    if (A.out < B.in) {
        @compileError("A.out < B.in");
    }

    if (A.in < B.out) {
        @compileError("A.in < B.out");
    }

    return struct {
        const Self = @This();
        pub usingnamespace NodeInterface(Self);

        pub const in = A.in - B.out;
        pub const out = A.out - B.in;

        a: A = undefined,
        b: B = undefined,
        mem: [B.in]f32 = undefined,

        pub fn eval(self: *Self, input: [in]f32) [out]f32 {
            // eval B from previous iteration
            const output_b = self.b.eval(self.mem);
            // concat external input to match A.in
            const input_a = output_b ++ input;
            // evaluate A
            const output_a = self.a.eval(input_a);
            // store first part into mem, return second part
            self.mem = output_a[0..B.in].*;
            return output_a[B.in..].*;
        }
    };
}

test "rec operator" {
    const A = Id(2).merge(Id(1)).split(Id(2));
    try ee(2, A.in);
    try ee(2, A.out);
    const B = Id(1);
    const N = Rec(A, B);
    try ee(1, N.in);
    try ee(1, N.out);
    var n = N{};
    for (1..5) |i| {
        const exp: f32 = @floatFromInt(i);
        const out = n.eval(.{1});
        try ee([_]f32{exp}, out);
    }
}

/// split operator : duplicate A.Output to match B.Input
fn Split(comptime A: type, comptime B: type) type {
    if (A.out > B.in) {
        @compileError("A.out > B.in");
    }

    if (B.in % A.out != 0) {
        @compileError("B.in % A.out != 0");
    }

    const repeat = @divExact(B.in, A.out);

    return struct {
        const Self = @This();
        pub usingnamespace NodeInterface(Self);

        pub const in = A.in;
        pub const out = B.out;

        a: A = undefined,
        b: B = undefined,

        pub fn eval(self: *Self, input: [in]f32) [out]f32 {
            const output_a = self.a.eval(input);
            return self.b.eval(output_a ** repeat);
        }
    };
}

test "split" {
    const N = Split(Id(2), Id(4));
    try ee(2, N.in);
    try ee(4, N.out);
    var n = N{};
    const input = [_]f32{ 1, 2 };
    const expected = [_]f32{ 1, 2, 1, 2 };
    const output = n.eval(input);
    try ee(expected, output);
}

// merge operator : reduce (add) A.Output to match B.Input
fn Merge(comptime A: type, comptime B: type) type {
    // checking length
    if (A.out < B.in) {
        @compileError("A.out < B.in");
    }

    if (A.out % B.in != 0) {
        @compileError("A.out % B.in != 0");
    }

    return struct {
        const Self = @This();
        pub usingnamespace NodeInterface(Self);

        pub const in = A.in;
        pub const out = B.out;

        a: A = undefined,
        b: B = undefined,

        pub fn eval(self: *Self, input: [in]f32) [out]f32 {
            const output_a = self.a.eval(input);
            var input_b = [_]f32{0} ** B.in;
            inline for (output_a, 0..) |v, i| {
                input_b[i % B.in] += v;
            }
            return self.b.eval(input_b);
        }
    };
}

test "merge operator" {
    const N = Merge(Id(4), Id(2));
    try ee(4, N.in);
    try ee(2, N.out);
    var n = N{};
    const input = [_]f32{ 1, 2, 3, 4 };
    const expected = [_]f32{ 4, 6 };
    const output = n.eval(input);
    try ee(expected, output);
}
