const std = @import("std");
const Tuple = std.meta.Tuple;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test {
    _ = Noize(48000);
}

fn Sub(comptime T: type, comptime low: usize, comptime high: usize) type {
    const info = @typeInfo(T);
    const old_fields = std.meta.fields(T)[low..high];
    var new_fields: [old_fields.len]std.builtin.Type.StructField = undefined;
    for (old_fields, 0..) |old, i| {
        new_fields[i] = .{
            .name = std.fmt.comptimePrint("{d}", .{i}),
            .type = old.type,
            .default_value = old.default_value,
            .alignment = old.alignment,
            .is_comptime = old.is_comptime,
        };
    }
    return @Type(.{
        .Struct = .{
            .layout = info.Struct.layout,
            .fields = &new_fields,
            .decls = &.{},
            .is_tuple = true,
        },
    });
}

fn Split(comptime T: type, comptime pivot: usize) type {
    const fields = std.meta.fields(T);
    return std.meta.Tuple(&[_]type{
        Sub(T, 0, pivot),
        Sub(T, pivot, fields.len),
    });
}

/// extract the subpart of a tuple in the given range
fn sub(tuple: anytype, comptime low: usize, comptime high: usize) Sub(@TypeOf(tuple), low, high) {
    var out: Sub(@TypeOf(tuple), low, high) = undefined;
    inline for (low..high, 0..) |i, o| {
        out[o] = tuple[i];
    }
    return out;
}

/// split a tuple in two at pivot point
fn split(tuple: anytype, comptime pivot: usize) Split(@TypeOf(tuple), pivot) {
    const fields = std.meta.fields(@TypeOf(tuple));
    return .{
        sub(tuple, 0, pivot),
        sub(tuple, pivot, fields.len),
    };
}

pub fn Noize(comptime samplerate: usize) type {
    return struct {
        const Self = @This();

        pub const step: f32 = 1 / @as(f32, @floatFromInt(samplerate));

        /// root node, evaluates a complete frame
        pub fn Root(comptime N: type) type {
            return struct {
                node: N = N{}, // root node

                pub inline fn eval(
                    self: *@This(),
                    nframes: usize,
                    input: [N.Input.len][]f32,
                    output: [N.Output.len][]f32,
                ) void {
                    const In = Tuple(&N.Input);
                    const Out = Tuple(&N.Output);
                    for (0..nframes) |i| {
                        var in: In = undefined;
                        inline for (0..N.Input.len) |j| {
                            in[j] = input[j][i];
                        }
                        const out: Out = self.node.eval(in);
                        inline for (0..N.Output.len) |j| {
                            output[j][i] = out[j];
                        }
                    }
                }
            };
        }

        /// sequence operator, A --> B
        /// if A.Output > B.Input, spare outputs are added to Seq's outputs
        /// if A.Output < B.Input, spare inputs are added to Seq's inputs
        pub fn Seq(comptime A: type, comptime B: type) type {
            for (0..@min(A.Output.len, B.Input.len)) |idx| {
                if (A.Output[idx] != B.Input[idx]) {
                    @compileError("type mismatch");
                }
            }

            const diff = @as(i32, A.Output.len) - @as(i32, B.Input.len);
            // diff>0 --> spare outputs
            // diff<0 --> spare inputs

            return struct {
                pub const Input = if (diff < 0) A.Input ++ B.Input[A.Output.len..].* else A.Input;
                pub const Output = if (diff > 0) B.Output ++ A.Output[B.Input.len..].* else B.Output;

                a: A = undefined,
                b: B = undefined,

                pub inline fn eval(self: *@This(), input: Tuple(&Input)) Tuple(&Output) {
                    if (diff > 0) {
                        // spare outputs of A are routed to the main output
                        const output_a = self.a.eval(input);
                        const input_b, const spare = split(output_a, B.Input.len);
                        const output_b = self.b.eval(input_b);
                        return output_b ++ spare;
                    } else if (diff < 0) {
                        // spare inputs of B are routed from the main input
                        const input_a, const spare = split(input, A.Input.len);
                        const output_a = self.a.eval(input_a);
                        const input_b = output_a ++ spare;
                        return self.b.eval(input_b);
                    } else {
                        return self.b.eval(self.a.eval(input));
                    }
                }
            };
        }

        test "seq" {
            const N = Self.Seq(Id(u8), Id(u8));
            var n = N{};
            const expected = Tuple(&N.Output){23};
            const output = n.eval(expected);
            try expectEqual(expected, output);
        }

        test "seq spare outputs" {
            const N = Self.Seq(
                Fork(Id(u8)),
                Add(u8, 1),
            );
            var n = N{};
            const output = n.eval(.{23});
            try expectEqual(.{ 24, 23 }, output);
        }

        test "seq spare inputs" {
            const N = Self.Seq(
                Id(u8),
                Sum(u8),
            );
            var n = N{};
            const output = n.eval(.{ 1, 2 });
            try expectEqual(.{1 + 2}, output);
        }

        /// apply Seq to a a slice of nodes
        pub fn SeqN(comptime Nodes: []const type) type {
            return switch (Nodes.len) {
                0 => @compileError("sequence at least two nodes"),
                1 => Nodes[0],
                2 => Self.Seq(Nodes[0], Nodes[1]),
                else => Self.SeqN(
                    [_]type{Self.Seq(Nodes[0], Nodes[1])} ++ Nodes[2..],
                ),
            };
        }

        test "seqN" {
            const N = Self.SeqN(&[_]type{ Self.Id(u8), Self.Id(u8), Self.Id(u8) });
            var n = N{};
            const expected = Tuple(&N.Output){23};
            const output = n.eval(.{23});
            try expectEqual(expected, output);
        }

        /// parallel operator : combine A and B in parallel
        pub fn Par(comptime A: type, comptime B: type) type {
            return struct {
                pub const Input = A.Input ++ B.Input;
                pub const Output = A.Output ++ B.Output;
                a: A = A{},
                b: B = B{},

                pub inline fn eval(self: *@This(), input: Tuple(&Input)) Tuple(&Output) {
                    const input_a, const input_b = split(input, A.Input.len);
                    return self.a.eval(input_a) ++ self.b.eval(input_b);
                }
            };
        }

        test "par" {
            const N = Self.Par(Self.Id(u8), Self.Id(u8));
            var n = N{};
            const expected = Tuple(&N.Output){ 23, 42 };
            const output = n.eval(expected);
            try expectEqual(expected, output);
        }

        /// apply parallel to a slice of nodes
        pub fn ParN(comptime Nodes: []const type) type {
            return switch (Nodes.len) {
                0 => @compileError("not enough nodes"),
                1 => Nodes[0],
                2 => Self.Par(Nodes[0], Nodes[1]),
                else => Self.ParN(
                    [_]type{Self.Par(Nodes[0], Nodes[1])} ++ Nodes[2..],
                ),
            };
        }

        test "parN" {
            const N = Self.Dup(Self.Id(u8), 3);
            var n = N{};
            const expected = Tuple(&N.Output){ 23, 42, 66 };
            const output = n.eval(expected);
            try expectEqual(expected, output);
        }

        // merge operator : reduce (add) A.Output to match B.Input
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
            const N = Self.Merge(
                Self.Dup(Self.Id(u8), 4),
                Self.Dup(Id(u8), 2),
            );
            var n = N{};
            const input = Tuple(&N.Input){ 1, 2, 3, 4 };
            const expected = Tuple(&N.Output){ 4, 6 };
            const output = n.eval(input);
            try expectEqual(expected, output);
        }

        /// split operator : duplicate A.Output to match B.Input
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
            const N = Self.Split(
                Self.Dup(Self.Id(u8), 2),
                Self.Dup(Self.Id(u8), 4),
            );
            var n = N{};
            const input = Tuple(&N.Input){ 1, 2 };
            const expected = Tuple(&N.Output){ 1, 2, 1, 2 };
            const output = n.eval(input);
            try expectEqual(expected, output);
        }

        /// recursive operator
        /// loop A --> B --> A
        /// A --> B is delayed one sample to avoid infinite loop
        /// spare inputs and outputs of A are Rec's IO
        pub fn Rec(comptime A: type, comptime B: type) type {
            if (A.Output.len < B.Input.len) {
                @compileError("A.Output >= B.Input not verified");
            }

            if (A.Input.len < B.Output.len) {
                @compileError("A.Input >= B.Output not verified");
            }

            if (!std.mem.eql(type, B.Input[0..], A.Output[0..B.Input.len])) {
                @compileError("type mismatch A --> B");
            }

            if (!std.mem.eql(type, B.Output[0..], A.Input[0..B.Output.len])) {
                @compileError("type mismatch B --> A");
            }

            return struct {
                pub const Input = A.Input[B.Output.len..].*;
                pub const Output = A.Output[B.Input.len..].*;

                a: A = undefined,
                b: B = undefined,
                mem: Tuple(&B.Input) = undefined,

                pub inline fn eval(self: *@This(), input: Tuple(&Input)) Tuple(&Output) {
                    // eval B from previous iteration
                    const output_b = self.b.eval(self.mem);
                    // concat external input to match A.Input
                    const input_a = output_b ++ input;
                    // evaluate A and store result in mem
                    const output_a = self.a.eval(input_a);
                    self.mem, const output = split(output_a, B.Input.len);
                    return output;
                }
            };
        }

        test "rec" {
            const N = Self.Rec(
                Self.Fork(Self.Sum(u8)),
                Id(u8),
            );
            var n = N{};
            for (1..5) |i| {
                const out = n.eval(.{1});
                try expectEqual(.{i}, out);
            }
        }

        /// identity function
        pub fn Id(comptime T: type) type {
            return struct {
                pub const Input = [1]type{T};
                pub const Output = [1]type{T};

                pub inline fn eval(self: *@This(), input: Tuple(&Input)) Tuple(&Output) {
                    _ = self;
                    return input;
                }
            };
        }

        test "id" {
            const N = Self.Id(u8);
            var n = N{};
            const expected = Tuple(&N.Output){23};
            const output = n.eval(expected);
            try expectEqual(expected, output);
        }

        /// identity function with multiple lines in parallel. Takes a tuple of types T and repeat it N times
        pub fn Bus(comptime T: type, comptime N: usize) type {
            return struct {
                pub const Input = [T.len]T ** N;
                pub const Output = [T.len]T ** N;

                pub inline fn eval(self: *@This(), input: Tuple(&Input)) Tuple(&Output) {
                    _ = self;
                    return input;
                }
            };
        }

        pub fn Fork(comptime N: type) type {
            return struct {
                pub const Input = N.Input;
                pub const Output = N.Output ** 2;

                n: N = undefined,

                pub inline fn eval(self: *@This(), input: Tuple(&Input)) Tuple(&Output) {
                    return self.n.eval(input) ** 2;
                }
            };
        }

        test "fork" {
            const N = Self.Fork(Self.Id(u8));
            var n = N{};
            const output = n.eval(.{23});
            try expectEqual(.{ 23, 23 }, output);
        }

        /// duplicates S times a node of type N and stacks them in parallel
        pub fn Dup(comptime N: type, comptime S: usize) type {
            return ParN(&[_]type{N} ** S);
        }

        test "dup" {
            const N = Self.Dup(Self.Id(u8), 2);
            var n = N{};
            const input = Tuple(&N.Output){ 1, 2 };
            const output = n.eval(input);
            try expectEqual(input, output);
        }

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
            const N = Self.Const(u8, 23);
            var n = N{};
            const expected: Tuple(&N.Output) = .{23};
            const output = n.eval(.{});
            try expectEqual(expected, output);
        }

        pub fn Sum(comptime T: type) type {
            return struct {
                pub const Input = [2]type{ T, T };
                pub const Output = [1]type{T};

                fn eval(self: *@This(), input: Tuple(&Input)) Tuple(&Output) {
                    _ = self;
                    return .{input[0] + input[1]};
                }
            };
        }

        test "sum" {
            const N = Self.Sum(u8);
            var n = N{};
            const expected = Tuple(&N.Output){23 + 42};
            const output = n.eval(.{ 23, 42 });
            try expectEqual(expected, output);
        }

        pub fn Add(comptime T: type, comptime value: T) type {
            return struct {
                pub const Input = [1]type{T};
                pub const Output = [1]type{T};

                fn eval(self: *@This(), input: Tuple(&Input)) Tuple(&Output) {
                    _ = self;
                    return .{input[0] + value};
                }
            };
        }

        /// multiply two entries
        pub fn Product(comptime T: type) type {
            return struct {
                pub const Input = [2]type{ T, T };
                pub const Output = [1]type{T};

                fn eval(self: *@This(), input: Tuple(&Input)) Tuple(&Output) {
                    _ = self;
                    return .{input[0] * input[1]};
                }
            };
        }

        test "product" {
            const N = Self.Product(u64);
            var n = N{};
            const expected = Tuple(&N.Output){23 * 42};
            const output = n.eval(.{ 23, 42 });
            try expectEqual(expected, output);
        }

        pub fn Mul(comptime T: type, comptime value: T) type {
            return struct {
                pub const Input = [1]type{T};
                pub const Output = [1]type{T};

                fn eval(self: *@This(), input: Tuple(&Input)) Tuple(&Output) {
                    _ = self;
                    return .{input[0] * value};
                }
            };
        }

        pub fn Rescale(comptime T: type, comptime srcMin: T, comptime srcMax: T, comptime dstMin: T, comptime dstMax: T) type {
            const scaleIn = srcMax - srcMin;
            const scaleOut = dstMax - dstMin;
            const scale = scaleOut / scaleIn;

            return struct {
                pub const Input = [1]type{T};
                pub const Output = [1]type{T};

                fn eval(self: *@This(), input: Tuple(&Input)) Tuple(&Output) {
                    _ = self;
                    const out = @mulAdd(T, input[0] - srcMin, scale, dstMin);
                    return .{out};
                }
            };
        }

        test "Rescale" {
            const data = [_][6]f32{
                [_]f32{ 0, 1, 0, 100, 0, 0 },
                [_]f32{ 0, 1, 0, 100, 1, 100 },
                [_]f32{ -1, 1, 0, 100, 0, 50 },
            };
            inline for (data) |d| {
                var n = Self.Rescale(f32, d[0], d[1], d[2], d[3]){};
                const out = n.eval(.{d[4]});
                try expectEqual(d[5], out[0]);
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
            const N = Self.Mem(u8, 1);
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
                    const read = (self.pos + length) % S;
                    const v = self.mem[read];
                    self.mem[self.pos] = input[0];
                    self.pos = (self.pos + 1) % S;
                    return .{v};
                }
            };
        }

        test "delay" {
            const N = Self.Delay(u8, 1);
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
            const N = Self.Loop(u8, data.len, data);
            var n = N{};
            for (0..data.len * 2) |i| {
                const out = n.eval(.{});
                try expectEqual(data[i % data.len], out[0]);
            }
        }

        /// sinewave at the given frequency
        pub fn Sin() type {
            return struct {
                pub const Input = [1]type{f32};
                pub const Output = [1]type{f32};

                phase: f32 = 0,

                const Self = @This();
                pub inline fn eval(self: *@This(), input: Tuple(&Input)) Tuple(&Output) {
                    const tau = std.math.tau;
                    const v = @sin(self.phase);
                    const freq = input[0];
                    self.phase = @mod(self.phase + freq * step * tau, tau);
                    return .{v};
                }
            };
        }

        /// add two entries
        pub fn Mix(comptime T: type, comptime mix: T) type {
            return struct {
                pub const Input = [2]type{ T, T };
                pub const Output = [1]type{T};

                fn eval(self: *@This(), input: Tuple(&Input)) Tuple(&Output) {
                    _ = self;
                    return .{input[0] * (1 - mix) + input[1] * mix};
                }
            };
        }

        pub fn FloatToInt(comptime F: type, comptime T: type) type {
            return struct {
                pub const Input = [1]type{F};
                pub const Output = [1]type{T};

                fn eval(self: *@This(), input: Tuple(&Input)) Tuple(&Output) {
                    _ = self;
                    return .{
                        @as(T, @intFromFloat(input[0])),
                    };
                }
            };
        }

        test "FloatToInt" {
            const N = Self.FloatToInt(f32, i32);
            var n = N{};
            const out = n.eval(.{23});
            try expectEqual(@as(i32, 23), out[0]);
        }

        pub fn ToFloat(comptime T: type) type {
            return struct {
                pub const Input = [1]type{T};
                pub const Output = [1]type{f32};

                fn eval(self: *@This(), input: Tuple(&Input)) Tuple(&Output) {
                    _ = self;
                    return .{
                        @as(f32, @floatFromInt(input[0])),
                    };
                }
            };
        }

        pub fn Stereo(comptime T: type) type {
            if (T.Output.len != 1) {
                @compileError("T should have one output");
            }

            return Self.Split(T, Self.Par(
                Self.Id(T.Output[0]),
                Self.Id(T.Output[0]),
            ));
        }
    };
}
