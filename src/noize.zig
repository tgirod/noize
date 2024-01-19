const std = @import("std");
const Tuple = std.meta.Tuple;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test {
    _ = Noize(48000);
}

pub fn Noize(comptime samplerate: usize) type {
    return struct {
        const Self = @This();

        pub const step: f32 = 1 / @as(f32, @floatFromInt(samplerate));

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
            const N = Self.Seq(Id(u8), Id(u8));
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
            const N = Self.Par(Self.Id(u8), Self.Id(u8));
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
            const N = Self.Rec(
                Self.Sum(u8),
                Self.Id(u8),
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

        test "add" {
            const N = Self.Sum(u8);
            var n = N{};
            const expected = Tuple(&N.Output){23 + 42};
            const output = n.eval(.{ 23, 42 });
            try expectEqual(expected, output);
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

        test "mul" {
            const N = Self.Product(u64);
            var n = N{};
            const expected = Tuple(&N.Output){23 * 42};
            const output = n.eval(.{ 23, 42 });
            try expectEqual(expected, output);
        }

        /// (entry * mul) + add
        pub fn MulAdd(comptime T: type, comptime mul: T, comptime add: T) type {
            return struct {
                pub const Input = [1]type{T};
                pub const Output = [1]type{T};

                fn eval(self: *@This(), input: Tuple(&Input)) Tuple(&Output) {
                    _ = self;
                    return .{@mulAdd(T, input[0], mul, add)};
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

        /// the main struct, that should connect to the outside
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
    };
}
