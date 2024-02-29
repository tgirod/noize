// This file contains the 5 basic operators used to combine nodes:
// - Seq: combine A and B in sequence
// - Par: combine A and B in parallel
// - Split: fan-out A's outputs to B's inputs
// - Merge: fan-in A's outputs to B's inputs
// - Rec: combine A and B in parallel

const std = @import("std");
const testing = std.testing;
const ee = testing.expectEqual;

const base = @import("./base.zig");

/// sequence operator, A --> B
/// if A.out < B.in, spare inputs are added to Seq's inputs
/// if A.out > B.in, spare outputs are added to Seq's outputs
pub fn Seq(comptime A: type, comptime B: type) type {
    return struct {
        pub const in = if (A.out < B.in) A.in + B.in - A.out else A.in;
        pub const out = if (A.out > B.in) B.out + A.out - B.in else B.out;

        a: A = undefined,
        b: B = undefined,

        pub fn eval(self: *@This(), input: [in]f32) [out]f32 {
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
    const PlusOne = base.MulAdd(1, 1);
    const N = Seq(PlusOne, PlusOne);
    try ee(1, N.in);
    try ee(1, N.out);
    var n = N{};
    const expected = [_]f32{23 + 2};
    const output = n.eval(.{23});
    try ee(expected, output);
}

test "seq operator spare inputs" {
    const N = Seq(base.Id(1), base.Id(2));
    try ee(2, N.in);
    try ee(2, N.out);
}

test "seq operator spare outputs" {
    const N = Seq(base.Id(2), base.Id(1));
    try ee(2, N.in);
    try ee(2, N.out);
}

/// apply Seq to a a slice of nodes
pub fn SeqN(comptime Nodes: []const type) type {
    return switch (Nodes.len) {
        0 => @compileError("sequence at least two nodes"),
        1 => Nodes[0],
        2 => Seq(Nodes[0], Nodes[1]),
        else => SeqN(
            [_]type{Seq(Nodes[0], Nodes[1])} ++ Nodes[2..],
        ),
    };
}

test "SeqN" {
    const PlusOne = base.MulAdd(1, 1);
    const N = SeqN(&[_]type{ PlusOne, base.Id(2), base.Id(3) });
    try ee(3, N.in);
    try ee(3, N.out);
    var n = N{};
    const expected = [_]f32{ 24, 23, 23 };
    const output = n.eval(.{ 23, 23, 23 });
    try ee(expected, output);
}

/// SeqIter calls `constructor` `size` times and combine the nodes in sequence
/// each call receive the index of the iterator as argument
pub fn SeqIter(comptime size: usize, comptime constructor: fn (comptime usize) type) type {
    comptime var nodes: [size]type = undefined;
    for (0..size) |i| {
        nodes[i] = constructor(i);
    }
    return SeqN(&nodes);
}

test "SeqIter" {
    const Add = Merge(base.Id(2), base.Id(1));
    const Anon = struct {
        fn constructor(comptime _: usize) type {
            return Add;
        }
    };

    const N = SeqIter(3, Anon.constructor);
    try ee(4, N.in);
    try ee(1, N.out);
    var n = N{};
    try ee([_]f32{1 + 2 + 3 + 4}, n.eval(.{ 1, 2, 3, 4 }));
}

/// parallel operator : combine A and B in parallel
pub fn Par(comptime A: type, comptime B: type) type {
    return struct {
        pub const in = A.in + B.in;
        pub const out = A.out + B.out;

        a: A = undefined,
        b: B = undefined,

        pub fn eval(self: *@This(), input: [in]f32) [out]f32 {
            return self.a.eval(input[0..A.in].*) ++ self.b.eval(input[A.in..].*);
        }
    };
}

test "par operator" {
    const N = Par(base.Id(2), base.Id(3));
    try ee(5, N.in);
    try ee(5, N.out);
    var n = N{};
    const expected = [_]f32{ 1, 2, 3, 4, 5 };
    const output = n.eval(expected);
    try ee(expected, output);
}

/// apply Par to a slice of nodes
pub fn ParN(comptime Nodes: []const type) type {
    return switch (Nodes.len) {
        0 => @compileError("not enough nodes"),
        1 => Nodes[0],
        2 => Par(Nodes[0], Nodes[1]),
        else => ParN(
            .{Par(Nodes[0], Nodes[1])} ++ Nodes[2..],
        ),
    };
}

test "parN" {
    const N = ParN(&[_]type{ base.Id(1), base.Id(1), base.Id(1) });
    try ee(3, N.in);
    try ee(3, N.out);
    var n = N{};
    const expected = [_]f32{ 23, 42, 66 };
    const output = n.eval(expected);
    try ee(expected, output);
}

/// ParIter calls `constructor` `size` times and combine the nodes in parallel
/// each call receive the index of the iterator as argument
pub fn ParIter(comptime size: usize, comptime constructor: fn (comptime usize) type) type {
    comptime var nodes: [size]type = undefined;
    for (0..size) |i| {
        nodes[i] = constructor(i);
    }
    return ParN(&nodes);
}

test "ParIter" {
    const Anon = struct {
        fn constructor(comptime i: usize) type {
            return base.Id(i + 1);
        }
    };

    const N = ParIter(3, Anon.constructor);
    try ee(6, N.in);
    try ee(6, N.out);
    var n = N{};
    try ee([_]f32{ 1, 2, 3, 4, 5, 6 }, n.eval(.{ 1, 2, 3, 4, 5, 6 }));
}

// merge operator : reduce (add) A.Output to match B.Input
pub fn Merge(comptime A: type, comptime B: type) type {
    // checking length
    if (A.out < B.in) {
        @compileError("A.out < B.in");
    }

    if (A.out % B.in != 0) {
        @compileError("A.out % B.in != 0");
    }

    return struct {
        pub const in = A.in;
        pub const out = B.out;

        a: A = undefined,
        b: B = undefined,

        pub fn eval(self: *@This(), input: [in]f32) [out]f32 {
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
    const N = Merge(base.Id(4), base.Id(2));
    try ee(4, N.in);
    try ee(2, N.out);
    var n = N{};
    const input = [_]f32{ 1, 2, 3, 4 };
    const expected = [_]f32{ 4, 6 };
    const output = n.eval(input);
    try ee(expected, output);
}

/// split operator : duplicate A.Output to match B.Input
pub fn Split(comptime A: type, comptime B: type) type {
    if (A.out > B.in) {
        @compileError("A.out > B.in");
    }

    if (B.in % A.out != 0) {
        @compileError("B.in % A.out != 0");
    }

    const repeat = @divExact(B.in, A.out);

    return struct {
        pub const in = A.in;
        pub const out = B.out;

        a: A = undefined,
        b: B = undefined,

        pub fn eval(self: *@This(), input: [in]f32) [out]f32 {
            const output_a = self.a.eval(input);
            return self.b.eval(output_a ** repeat);
        }
    };
}

test "split" {
    const N = Split(base.Id(2), base.Id(4));
    try ee(2, N.in);
    try ee(4, N.out);
    var n = N{};
    const input = [_]f32{ 1, 2 };
    const expected = [_]f32{ 1, 2, 1, 2 };
    const output = n.eval(input);
    try ee(expected, output);
}

/// recursive operator
/// loop A --> B --> A
/// A --> B is delayed one sample to avoid infinite loop
/// spare inputs and outputs of A are Rec's IO
pub fn Rec(comptime A: type, comptime B: type) type {
    if (A.out < B.in) {
        @compileError("A.out < B.in");
    }

    if (A.in < B.out) {
        @compileError("A.in < B.out");
    }

    return struct {
        pub const in = A.in - B.out;
        pub const out = A.out - B.in;

        a: A = undefined,
        b: B = undefined,
        mem: [B.in]f32 = undefined,

        pub fn eval(self: *@This(), input: [in]f32) [out]f32 {
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
    const Sum = Merge(base.Id(2), base.Id(1));
    try ee(2, Sum.in);
    try ee(1, Sum.out);
    const A = Split(Sum, base.Id(2));
    try ee(2, A.in);
    try ee(2, A.out);
    const B = base.Id(1);
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
