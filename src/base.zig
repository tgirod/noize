const std = @import("std");
const testing = std.testing;
const ee = testing.expectEqual;

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
    const PlusOne = MulAdd(1, 1);
    const N = SeqN(&[_]type{ PlusOne, Id(2), Id(3) });
    try ee(3, N.in);
    try ee(3, N.out);
    var n = N{};
    const expected = [_]f32{ 24, 23, 23 };
    const output = n.eval(.{ 23, 23, 23 });
    try ee(expected, output);
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
    const N = Par(Id(2), Id(3));
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
    const N = ParN(&[_]type{ Id(1), Id(1), Id(1) });
    try ee(3, N.in);
    try ee(3, N.out);
    var n = N{};
    const expected = [_]f32{ 23, 42, 66 };
    const output = n.eval(expected);
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
    const A = Seq(Merge(2, 1), Split(1, 2));
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

/// reduce inputs by adding them to match output size
/// eg: for Merge(6,2), {a,b,c,d,e,f} --> {a+c+e, b+d+f}
pub fn Merge(comptime i: usize, comptime o: usize) type {
    // checking length
    if (i < o) {
        @compileError("i < o");
    }

    if (i % o != 0) {
        @compileError("i % o != 0");
    }

    return struct {
        pub const in = i;
        pub const out = o;

        pub fn eval(self: *@This(), input: [in]f32) [out]f32 {
            _ = self;
            var output = [_]f32{0} ** out;
            inline for (input, 0..) |v, idx| {
                output[idx % out] += v;
            }
            return output;
        }
    };
}

test "merge" {
    const N = Merge(4, 2);
    try ee(4, N.in);
    try ee(2, N.out);
    var n = N{};
    try ee([_]f32{ 4, 6 }, n.eval([_]f32{ 1, 2, 3, 4 }));
}

/// duplicate inputs to match output size
pub fn Split(comptime i: usize, comptime o: usize) type {
    if (i > o) {
        @compileError("i > o");
    }

    if (o % i != 0) {
        @compileError("o % i != 0");
    }

    const repeat = @divExact(o, i);

    return struct {
        pub const in = i;
        pub const out = o;

        pub fn eval(self: *@This(), input: [in]f32) [out]f32 {
            _ = self;
            return input ** repeat;
        }
    };
}

test "split" {
    const N = Split(2, 4);
    try ee(2, N.in);
    try ee(4, N.out);
    var n = N{};
    try ee([_]f32{ 1, 2, 1, 2 }, n.eval([_]f32{ 1, 2 }));
}

// Identity function
pub fn Id(comptime size: usize) type {
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

// Multiply by and add
pub fn MulAdd(comptime mul: f32, comptime add: f32) type {
    return struct {
        pub const in = 1;
        pub const out = 1;

        pub fn eval(_: *@This(), input: [in]f32) [out]f32 {
            return .{@mulAdd(f32, input[0], mul, add)};
        }
    };
}

test "MulAdd" {
    var n = MulAdd(3, 4){};
    const output = n.eval(.{23});
    try ee(.{23 * 3 + 4}, output);
}

/// Always return the same values
pub fn Const(comptime args: anytype) type {
    const values: [args.len]f32 = args;

    return struct {
        pub const in = 0;
        pub const out = values.len;
        pub fn eval(_: *@This(), _: [in]f32) [out]f32 {
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

pub fn Sum() type {
    return struct {
        pub const in = 2;
        pub const out = 1;
        pub fn eval(_: *@This(), input: [in]f32) [out]f32 {
            return [_]f32{input[0] + input[1]};
        }
    };
}
