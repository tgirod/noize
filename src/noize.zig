const std = @import("std");
const Tuple = std.meta.Tuple;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const srate: f64 = 48000;

/// the main struct, that should connect to the outside
pub fn Noize(comptime N: type) type {
    return struct {
        node: N = N{}, // root node
        in: Tuple(&N.Input),
        out: Tuple(&N.Output),

        pub inline fn eval(self: *@This()) void {
            self.out = self.eval(self.in);
        }
    };
}

/// identity function, mostly for testing purpose
pub fn Id(comptime T: type) type {
    return struct {
        pub const Input = [1]type{T};
        pub const Output = [1]type{T};

        pub inline fn eval(self: *@This(), input: Tuple(&Input)) Tuple(&Output) {
            _ = self;
            return .{input[0]};
        }
    };
}

test "id" {
    const N = Id(u8);
    var n = N{};
    const expected = Tuple(&N.Output){23};
    const output = n.eval(expected);
    try expectEqual(expected, output);
}

/// always evaluate to the value passed at comptime
pub fn Const(comptime T: type, comptime value: T) type {
    return struct {
        pub const Input = [0]type{};
        pub const Output = [1]type{T};

        pub inline fn eval(self: *@This(), input: Tuple(&Input)) Tuple(&Output) {
            _ = input;
            _ = self;
            return .{value};
        }
    };
}

test "const" {
    const N = Const(u8, 23);
    var n = N{};
    const expected: Tuple(&N.Output) = .{23};
    const output = n.eval(.{});
    try expectEqual(expected, output);
}

/// add two entries
pub fn Add(comptime T: type) type {
    return struct {
        pub const Input = [2]type{ T, T };
        pub const Output = [1]type{T};

        fn eval(self: *@This(), input: Tuple(&Input)) Tuple(&Output) {
            _ = self;
            return .{input[0] + input[1]};
        }
    };
}

test "add" {
    const N = Add(u8);
    var n = N{};
    const expected = Tuple(&N.Output){23 + 42};
    const output = n.eval(.{ 23, 42 });
    try expectEqual(expected, output);
}

/// multiply two entries
pub fn Mul(comptime T: type) type {
    return struct {
        pub const Input = [2]type{ T, T };
        pub const Output = [1]type{T};

        fn eval(self: *@This(), input: Tuple(&Input)) Tuple(&Output) {
            _ = self;
            return .{input[0] * input[1]};
        }
    };
}

test "mul" {
    const N = Mul(u64);
    var n = N{};
    const expected = Tuple(&N.Output){23 * 42};
    const output = n.eval(.{ 23, 42 });
    try expectEqual(expected, output);
}

/// connect two nodes as a sequence
pub fn Seq(comptime A: type, comptime B: type) type {
    if (!std.mem.eql(type, &A.Output, &B.Input)) {
        @compileError("mismatch");
    }

    return struct {
        pub const Input = A.Input;
        pub const Output = B.Output;
        a: A = A{},
        b: B = B{},

        pub inline fn eval(self: *@This(), input: Tuple(&Input)) Tuple(&Output) {
            return self.b.eval(self.a.eval(input));
        }
    };
}

test "seq" {
    const N = Seq(Id(u8), Id(u8));
    var n = N{};
    const expected = Tuple(&N.Output){23};
    const output = n.eval(expected);
    try expectEqual(expected, output);
}

/// connect two nodes as a sequence
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

test "seqN" {
    const N = SeqN(&[_]type{ Id(u8), Id(u8), Id(u8) });
    var n = N{};
    const expected = Tuple(&N.Output){23};
    const output = n.eval(.{23});
    try expectEqual(expected, output);
}

/// combine two nodes in parallel
pub fn Par(comptime A: type, comptime B: type) type {
    return struct {
        pub const Input = A.Input ++ B.Input;
        pub const Output = A.Output ++ B.Output;
        a: A = A{},
        b: B = B{},

        pub inline fn eval(self: *@This(), input: Tuple(&Input)) Tuple(&Output) {
            var input_a: Tuple(&A.Input) = undefined;
            var input_b: Tuple(&B.Input) = undefined;
            inline for (input, 0..) |v, i| {
                if (i < input_a.len) {
                    input_a[i] = v;
                } else {
                    input_b[i - input_a.len] = v;
                }
            }
            return self.a.eval(input_a) ++ self.b.eval(input_b);
        }
    };
}

test "par" {
    const N = Par(Id(u8), Id(u8));
    var n = N{};
    const expected = Tuple(&N.Output){ 23, 42 };
    const output = n.eval(expected);
    try expectEqual(expected, output);
}

/// connect two nodes as a sequence
pub fn ParN(comptime Nodes: []const type) type {
    return switch (Nodes.len) {
        0 => @compileError("not enough nodes"),
        1 => Nodes[0],
        2 => Par(Nodes[0], Nodes[1]),
        else => ParN(
            [_]type{Par(Nodes[0], Nodes[1])} ++ Nodes[2..],
        ),
    };
}

test "parN" {
    const N = ParN(&[_]type{ Id(u8), Id(u8), Id(u8) });
    var n = N{};
    const expected = Tuple(&N.Output){ 23, 42, 66 };
    const output = n.eval(expected);
    try expectEqual(expected, output);
}

/// takes a size S and a node type N, and duplicate N S times in parallel
pub fn Dup(comptime N: type, comptime S: usize) type {
    return struct {
        nodes: [S]N = [1]N{N{}} ** S,

        pub const Input = N.Input ** S;
        pub const Output = N.Output ** S;

        pub inline fn eval(self: *@This(), input: Tuple(&Input)) Tuple(&Output) {
            // input for one node
            var in: Tuple(&N.Input) = undefined;
            // output for one node
            var out: Tuple(&N.Output) = undefined;
            // final output
            var output: Tuple(&Output) = undefined;

            inline for (0..S) |n| {
                // prepare input tuple
                inline for (0..in.len) |i| {
                    in[i] = input[n * in.len + i];
                }
                // evaluate node
                out = self.nodes[n].eval(in);
                // copy result to output
                inline for (0..out.len) |o| {
                    output[n * out.len + o] = out[o];
                }
            }

            return output;
        }
    };
}

test "dup" {
    const N = Dup(Id(u8), 2);
    var n = N{};
    const input = Tuple(&N.Output){ 1, 2 };
    const output = n.eval(input);
    try expectEqual(input, output);
}

pub fn Merge(comptime A: type, comptime B: type) type {
    // checking length
    const big = A.Output.len;
    const small = B.Input.len;
    if (big % small != 0) {
        @compileError("length mismatch");
    }

    // checking types
    const repeat = B.Input ** @divExact(big, small);
    if (!std.mem.eql(type, &repeat, &A.Output)) {
        @compileError("type mismatch");
    }

    return struct {
        pub const Input = A.Input;
        pub const Output = B.Output;
        a: A = A{},
        b: B = B{},

        pub inline fn eval(self: *@This(), input: Tuple(&Input)) Tuple(&Output) {
            const output_a = self.a.eval(input);
            var input_b: Tuple(&B.Input) = undefined;
            inline for (output_a, 0..) |v, i| {
                if (i < input_b.len) {
                    input_b[i] = v;
                } else {
                    input_b[i % small] += v;
                }
            }
            return self.b.eval(input_b);
        }
    };
}

test "merge" {
    const N = Merge(
        Par(
            Par(Const(u8, 1), Const(u8, 2)),
            Par(Const(u8, 3), Const(u8, 4)),
        ),
        Par(Id(u8), Id(u8)),
    );
    var n = N{};
    const expected = Tuple(&N.Output){ 4, 6 };
    const output = n.eval(.{});
    try expectEqual(expected, output);
}

pub fn Split(comptime A: type, comptime B: type) type {
    // checking length
    const small = A.Output.len;
    const big = B.Input.len;
    if (big % small != 0) {
        @compileError("length mismatch");
    }
    const ratio = @divExact(big, small);

    // checking types
    const repeat = A.Output ** ratio;
    if (!std.mem.eql(type, &repeat, &B.Input)) {
        @compileError("type mismatch");
    }

    return struct {
        pub const Input = A.Input;
        pub const Output = B.Output;
        a: A = A{},
        b: B = B{},

        pub inline fn eval(self: *@This(), input: Tuple(&Input)) Tuple(&Output) {
            const output_a = self.a.eval(input);
            return self.b.eval(output_a ** ratio);
        }
    };
}

test "split" {
    const N = Split(
        Dup(Id(u8), 2),
        Dup(Id(u8), 4),
    );
    var n = N{};
    const expected = Tuple(&N.Output){ 1, 2, 1, 2 };
    const output = n.eval(.{ 1, 2 });
    try expectEqual(expected, output);
}

pub fn Rec(comptime A: type, comptime B: type) type {
    if (B.Input.len != A.Output.len) {
        @compileError("length mismatch : A --> B");
    }

    if (!std.mem.eql(type, &B.Input, &A.Output)) {
        @compileError("type mismatch : A --> B");
    }

    if (A.Input.len < B.Output.len) {
        @compileError("length mismatch : B --> A");
    }

    if (!std.mem.eql(type, A.Input[0..B.Output.len], &B.Output)) {
        @compileError("type mismatch : B --> A");
    }

    const len = A.Input.len - B.Output.len;
    return struct {
        pub const Input = @as([len]type, A.Input[B.Output.len..].*);
        pub const Output = A.Output;
        a: A = A{},
        b: B = B{},
        mem: Tuple(&A.Output) = undefined,

        pub inline fn eval(self: *@This(), input: Tuple(&Input)) Tuple(&Output) {
            // eval B from previous iteration
            const output_b = self.b.eval(self.mem);
            // concat external input to match A.Input
            const input_a = output_b ++ input;
            // evaluate A and store result in mem
            self.mem = self.a.eval(input_a);
            return self.mem;
        }
    };
}

test "rec" {
    const N = Rec(
        Add(u8),
        Id(u8),
    );
    var n = N{};
    for (1..5) |i| {
        const out = n.eval(.{1});
        try expectEqual(.{i}, out);
    }
}

/// delay line with a fixed size
pub fn Mem(comptime T: type, comptime S: usize) type {
    if (S == 0) {
        @compileError("delay length == 0");
    }

    return struct {
        pub const Input = [1]type{T};
        pub const Output = [1]type{T};

        mem: [S]T = [1]T{0} ** S,
        pos: usize = 0,

        pub inline fn eval(self: *@This(), input: Tuple(&Input)) Tuple(&Output) {
            const v = self.mem[self.pos];
            self.mem[self.pos] = input[0];
            self.pos = (self.pos + 1) % S;
            return .{v};
        }
    };
}

test "mem" {
    const N = Mem(u8, 1);
    var n = N{};
    const input = [_]u8{ 1, 2, 3, 4, 5 };
    const expected = [_]u8{ 0, 1, 2, 3, 4 };
    for (input, expected) |i, e| {
        const out = n.eval(.{i});
        try expectEqual(e, out[0]);
    }
}

/// delay line with dynamic length (maximum size defined at comptime)
pub fn Delay(comptime T: type, comptime S: usize) type {
    if (S == 0) {
        @compileError("delay length == 0");
    }

    return struct {
        pub const Input = [2]type{ T, usize };
        pub const Output = [1]type{T};

        mem: [S]T = [1]T{0} ** S,
        pos: usize = 0,

        pub inline fn eval(self: *@This(), input: Tuple(&Input)) Tuple(&Output) {
            // clamping length to S
            const length = @min(input[1], S);
            if (length == 0) {
                // shortcircuit delay if length == 0
                return .{input[0]};
            } else {
                const read = (self.pos + length) % S;
                const v = self.mem[read];
                self.mem[self.pos] = input[0];
                self.pos = (self.pos + 1) % S;
                return .{v};
            }
        }
    };
}

test "delay" {
    const N = Delay(u8, 1);
    var n = N{};
    const input = [_]u8{ 1, 2, 3, 4, 5 };
    const expected = [_]u8{ 0, 1, 2, 3, 4 };
    for (input, expected) |i, e| {
        const out = n.eval(.{ i, 1 });
        try expectEqual(e, out[0]);
    }
}

/// loop over a buffer
// NOTE: not very useful, putting it as a basis for something else
pub fn Loop(
    comptime T: type,
    comptime S: usize,
    comptime data: [S]T,
) type {
    return struct {
        pub const Input = [0]type{};
        pub const Output = [1]type{T};

        mem: [S]T = data,
        pos: usize = 0,

        pub inline fn eval(self: *@This(), input: Tuple(&Input)) Tuple(&Output) {
            _ = input;
            const v = self.mem[self.pos];
            self.pos = (self.pos + 1) % S;
            return .{v};
        }
    };
}

test "loop" {
    const data = [4]u8{ 1, 2, 3, 4 };
    const N = Loop(u8, data.len, data);
    var n = N{};
    for (0..data.len * 2) |i| {
        const out = n.eval(.{});
        try expectEqual(data[i % data.len], out[0]);
    }
}

/// sinewave at the given frequency
pub fn Sin() type {
    return struct {
        pub const Input = [1]type{f64};
        pub const Output = [1]type{f64};

        phase: f64 = 0,

        const Self = @This();
        pub inline fn eval(self: *@This(), input: Tuple(&Input)) Tuple(&Output) {
            const v = @sin(self.phase);
            const freq = input[0];
            const step = freq * std.math.tau * 1 / srate;
            self.phase = @mod(self.phase + step, std.math.tau);
            return .{v};
        }
    };
}
