const std = @import("std");

const testing = std.testing;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const Tuple = std.meta.Tuple;

const tup = @import("tuple.zig");
pub usingnamespace @import("backend.zig");

test "test dispatch" {
    testing.refAllDecls(@This());
}

/// add NodeInterface to a node's namespace in order to add useful methods
pub fn NodeInterface(comptime Self: type) type {
    return struct {
        pub fn par(comptime Next: type) type {
            return Par(Self, Next);
        }

        pub fn seq(comptime Next: type) type {
            return Seq(Self, Next);
        }

        pub fn rec(comptime Feedback: type) type {
            return Rec(Self, Feedback);
        }

        pub fn dup(comptime size: usize) type {
            return Dup(Self, size);
        }
    };
}

/// parallel operator : combine A and B in parallel
pub fn Par(A: type, B: type) type {
    return struct {
        pub usingnamespace NodeInterface(Self);
        const Self = @This();

        pub const Input = tup.Join(A.Input, B.Input);
        pub const Output = tup.Join(A.Output, B.Output);

        a: A = undefined,
        b: B = undefined,

        pub fn init(self: *Self) void {
            self.a.init();
            self.b.init();
        }

        pub fn eval(self: *Self, input: Input) Output {
            const sp = tup.split(input, tup.len(A.Input));
            return self.a.eval(sp[0]) ++ self.b.eval(sp[1]);
        }
    };
}

test "parallel operator" {
    var n = Id(u8).par(Id(f32)){};
    n.init();
    try expectEqual(.{ 23, 42 }, n.eval(.{ 23, 42 }));
}

/// sequence operator, A --> B
/// spare inputs of B are exposed as inputs of Seq
/// spare outputs of A are exposed as outputs of Seq
pub fn Seq(comptime A: type, comptime B: type) type {
    return struct {
        pub usingnamespace NodeInterface(Self);
        const Self = @This();

        const diff = @as(comptime_int, tup.len(A.Output)) - @as(comptime_int, tup.len(B.Input));

        pub const Input = init: {
            if (diff < 0) {
                // add spare inputs of B
                const sp: tup.Split(B.Input, tup.len(A.Output)) = undefined;
                std.debug.assert(tup.typematch(@TypeOf(sp[0]), A.Output));
                break :init tup.Join(A.Input, @TypeOf(sp[1]));
            } else {
                break :init A.Input;
            }
        };

        pub const Output = init: {
            if (diff > 0) {
                // add spare outputs of A
                const sp: tup.Split(A.Output, tup.len(B.Input)) = undefined;
                std.debug.assert(tup.typematch(@TypeOf(sp[0]), B.Input));
                break :init tup.Join(B.Output, @TypeOf(sp[1]));
            } else {
                break :init B.Output;
            }
        };

        a: A = undefined,
        b: B = undefined,

        pub fn init(self: *Self) void {
            self.a.init();
            self.b.init();
        }

        pub fn eval(self: *Self, input: Input) Output {
            if (diff < 0) {
                // spare inputs of B are routed from the main input
                const sp = tup.split(input, tup.len(A.Input));
                const input_a: A.Input = sp[0];
                const spare = sp[1];
                const output_a: A.Output = self.a.eval(input_a);
                const input_b: B.Input = output_a ++ spare;
                return self.b.eval(input_b);
            } else if (diff > 0) {
                // spare outputs of A are routed to the main output
                const output_a: A.Output = self.a.eval(input);
                const sp = tup.split(output_a, tup.len(B.Input));
                const input_b: B.Input = sp[0];
                const spare = sp[1];
                const output_b: B.Output = self.b.eval(input_b);
                return output_b ++ spare;
            } else {
                // no spare input or output
                return self.b.eval(self.a.eval(input));
            }
        }
    };
}

test "seq - equal size" {
    var n = Id(u8).seq(Id(u8)){};
    n.init();
    try expectEqual(.{23}, n.eval(.{23}));
}

test "seq - spare inputs" {
    const A = Id(u8);
    const B = Id(u8).par(Id(bool));
    const N = A.seq(B);
    try expectEqual(2, tup.len(N.Input));
    try expectEqual(2, tup.len(N.Output));
    var n = N{};
    n.init();
    try expectEqual(.{ 23, false }, n.eval(.{ 23, false }));
}

test "seq - spare outputs" {
    const A = Id(u8).par(Id(bool));
    const B = Id(u8);
    const N = A.seq(B);
    try expectEqual(2, tup.len(N.Input));
    try expectEqual(2, tup.len(N.Output));
    var n = N{};
    n.init();
    try expectEqual(.{ 23, false }, n.eval(.{ 23, false }));
    try expectEqual(2, tup.len(N.Output));
}

/// recursive operator : loop A --> B --> A
/// A --> B is delayed one sample to avoid infinite loop
/// spare inputs of A are exposed as inputs of Rec
/// spare outputs of A are exposed as outputs of Rec
pub fn Rec(comptime A: type, comptime B: type) type {
    std.debug.assert(tup.len(B.Input) < tup.len(A.Output));
    std.debug.assert(tup.len(B.Output) < tup.len(A.Input));

    const split_input: tup.Split(A.Input, tup.len(B.Output)) = undefined;
    std.debug.assert(tup.typematch(B.Output, @TypeOf(split_input[0])));

    const split_output: tup.Split(A.Output, tup.len(B.Input)) = undefined;
    std.debug.assert(tup.typematch(B.Input, @TypeOf(split_output[0])));

    return struct {
        const Self = @This();
        pub usingnamespace NodeInterface(Self);

        pub const Input = @TypeOf(split_input[1]); // A's unmatched inputs
        pub const Output = @TypeOf(split_output[1]); // A's unmatched outputs

        a: A = undefined,
        b: B = undefined,
        mem: B.Input = undefined,

        pub fn init(self: *Self) void {
            self.a.init();
            self.b.init();
            self.mem = std.mem.zeroes(@TypeOf(self.mem));
        }

        pub fn eval(self: *Self, input: Input) Output {
            // eval B from previous iteration
            const output_b = self.b.eval(self.mem);
            // concat external input to match A.in
            const input_a = output_b ++ input;
            // evaluate A
            const output_a = self.a.eval(input_a);
            // store first part into mem, return second part
            const sp = tup.split(output_a, tup.len(B.Input));
            self.mem = sp[0];
            return sp[1];
        }
    };
}

test "rec" {
    const Cross = struct {
        const Self = @This();
        pub const Input = struct { u8, u8 };
        pub const Output = struct { u8, u8 };

        pub fn eval(_: *Self, input: Input) Output {
            const sum = input[0] + input[1];
            return .{ sum, sum };
        }

        pub fn init(_: *Self) void {}
    };

    const N = Rec(Cross, Id(u8));
    try expectEqual(1, tup.len(N.Input));
    try expectEqual(1, tup.len(N.Output));

    var n: N = undefined;
    n.init();
    try expectEqual(.{1}, n.eval(.{1}));
    try expectEqual(.{1}, n.mem);
    try expectEqual(.{2}, n.eval(.{1}));
}

// duplicate outputs of N size times
pub fn Dup(N: type, comptime size: usize) type {
    return struct {
        const Self = @This();
        pub usingnamespace NodeInterface(Self);

        pub const Input = N.Input;
        pub const Output = init: {
            const out: N.Output = undefined;
            break :init @TypeOf(out ** size);
        };

        node: N = undefined,

        pub fn init(self: *Self) void {
            self.node.init();
        }

        pub fn eval(self: *Self, input: Input) Output {
            const output = self.node.eval(input);
            return output ** size;
        }
    };
}

// pub fn Fork(A: type, B: type, comptime size: usize) type {
//     return struct {
//         const Self = @This();
//         pub usingnamespace NodeInterface(Self);

//         const diff = @as(comptime_int, tup.len(A.Output)) - @as(comptime_int, tup.len(B.Input));

//         pub const Input = init: {
//             if (diff < 0) {
//                 // add spare inputs of B
//                 const a_input: A.Input = undefined;
//                 const b_input: B.Input = undefined;
//                 const spare = tup.split(b_input, tup.len(A.Output))[1];
//                 break :init @TypeOf(a_input ++ (spare ** size));
//             } else {
//                 break :init A.Input;
//             }
//         };

//         pub const Output = init: {
//             if (diff > 0) {
//                 // add spare outputs of A
//                 const a_output: A.Output = undefined;
//                 const spare = tup.split(a_output, tup.len(B.Input))[1];
//                 const b_output: B.Output = undefined;
//                 break :init @TypeOf((b_output ** size) ++ spare);
//             } else {
//                 const b_output: B.Output = undefined;
//                 break :init @TypeOf(b_output ** size);
//             }
//         };

//         a: A = undefined,
//         b: [size]B = undefined,

//         pub fn init(self: *Self) void {
//             self.a.init();
//             for (0..size) |i| {
//                 self.b[i].init();
//             }
//         }

//         pub fn eval(self: *Self, input: Input) Output {
//             if (diff < 0) {
//                 // spare inputs of B are routed from the main input
//                 const split = tup.split(input, tup.len(A.Input));
//                 const input_a: A.Input = split[0];
//                 const spare = split[1];
//                 const output_a: A.Output = self.a.eval(input_a);
//                 // TODO pour chaque B, construire son input avec output_a + un morceau de spare ... c'est l'enfer si on ne peut pas slicer les tuples
//             }
//             const output = self.node.eval(input);
//             return output ** size;
//         }
//     };
// }

/// simplest node : identity function
pub fn Id(T: type) type {
    return struct {
        const Self = @This();
        pub usingnamespace NodeInterface(Self);

        pub const Input = struct { T };
        pub const Output = struct { T };

        pub fn init(_: *Self) void {}

        pub fn eval(_: *Self, input: Input) Output {
            return input;
        }
    };
}

/// multiply then add, useful for scaling
pub fn MulAdd(comptime mul: f32, comptime add: f32) type {
    return struct {
        const Self = @This();
        pub usingnamespace NodeInterface(Self);

        pub const Input = struct { f32 };
        pub const Output = struct { f32 };

        pub fn init(_: *Self) void {}

        pub fn eval(_: *Self, input: Input) Output {
            return .{@mulAdd(f32, input[0], mul, add)};
        }
    };
}

test "MulAdd" {
    const N = MulAdd(23, 42);
    var n = N{};
    try expectEqual(.{1 * 23 + 42}, n.eval(.{1}));
}

/// Always return the same value
pub fn Const(value: anytype) type {
    return struct {
        const Self = @This();
        pub usingnamespace NodeInterface(Self);

        pub const Input = struct {};
        pub const Output = struct {
            @TypeOf(value),
        };

        pub fn init(_: *Self) void {}

        pub fn eval(_: *Self, _: Input) Output {
            return .{value};
        }
    };
}

test "Const" {
    const N = Const(@as(u8, 23));
    var n = N{};
    n.init();
    try expectEqual(.{@as(u8, 23)}, n.eval(.{}));
}

/// sinewave at the given frequency
pub fn Sin(comptime srate: f32) type {
    const step: f32 = 1 / srate;
    const tau = std.math.tau;

    return struct {
        const Self = @This();
        pub usingnamespace NodeInterface(Self);

        pub const Input = struct {
            f32, // frequency
        };

        pub const Output = struct {
            f32, // signal
        };

        phase: f32,

        pub fn init(self: *Self) void {
            self.phase = 0;
        }

        pub fn eval(self: *Self, input: Input) Output {
            const v = @sin(self.phase * tau);
            const freq = input[0];
            self.phase = @mod(self.phase + freq * step, 1);
            return .{v};
        }
    };
}

pub fn BufWriter(T: type) type {
    return struct {
        const Self = @This();
        pub usingnamespace NodeInterface(Self);

        pub const Input = struct {
            T, // input signal
            []T, // buffer address
        };

        pub const Output = struct {
            usize, // write index
        };

        index: usize = 0,

        pub fn init(self: *Self) void {
            self.index = 0;
        }

        pub fn eval(self: *Self, input: Input) Output {
            var buf = input[1];
            self.index = (self.index + 1) % buf.len;
            buf[self.index] = input[0];
            return .{self.index};
        }
    };
}

test "bufwriter" {
    var buf = [1]u8{0} ** 3;

    const N = BufWriter(u8);
    var n = N{};
    n.init();

    try expectEqual(.{1}, n.eval(.{ 1, &buf }));
    try std.testing.expectEqualSlices(u8, &[3]u8{ 0, 1, 0 }, &buf);
    try expectEqual(.{2}, n.eval(.{ 1, &buf }));
    try std.testing.expectEqualSlices(u8, &[3]u8{ 0, 1, 1 }, &buf);
    try expectEqual(.{0}, n.eval(.{ 1, &buf }));
    try std.testing.expectEqualSlices(u8, &[3]u8{ 1, 1, 1 }, &buf);
}

pub fn BufReader(T: type) type {
    return struct {
        const Self = @This();
        pub usingnamespace NodeInterface(Self);

        pub const Input = struct {
            usize, // read index
            []T, // buffer address
        };

        pub const Output = struct {
            T, // output signal
        };

        pub fn init(_: *Self) void {}

        pub fn eval(_: *Self, input: Input) Output {
            const index = input[0];
            const buf = input[1];
            return .{buf[index % buf.len]};
        }
    };
}

test "BufReader" {
    var buf = [_]u8{ 1, 2, 3 };

    const N = BufReader(u8);
    var n = N{};
    n.init();

    try expectEqual(.{1}, n.eval(.{ 0, &buf }));
    try expectEqual(.{2}, n.eval(.{ 1, &buf }));
    try expectEqual(.{3}, n.eval(.{ 2, &buf }));
    try expectEqual(.{1}, n.eval(.{ 3, &buf }));
}

/// Linear interpolation of two inputs 0 and 1, based on the value of input 2
pub fn Lerp(comptime T: type) type {
    return struct {
        const Self = @This();
        pub usingnamespace NodeInterface(Self);

        pub const Input = struct {
            T, // first value
            T, // second value
            T, // interpolation factor
        };

        pub const Output = struct {
            T, // output signal
        };

        pub fn init(_: *Self) void {}

        pub fn eval(_: *Self, input: Input) Output {
            return .{std.math.lerp(input[0], input[1], input[2])};
        }
    };
}

test "Lerp" {
    const N = Lerp(f32);
    var n = N{};
    n.init();

    try expectEqual(.{0}, n.eval(.{ 0, 10, 0 }));
    try expectEqual(.{5}, n.eval(.{ 0, 10, 0.5 }));
    try expectEqual(.{10}, n.eval(.{ 0, 10, 1 }));
}

pub fn duration(comptime srate: f32) type {
    return struct {
        pub fn msec(n: f32) usize {
            return @intFromFloat(srate * n / 1000);
        }

        pub fn sec(n: f32) usize {
            return @intFromFloat(srate * n);
        }

        pub fn min(n: f32) usize {
            return @intFromFloat(srate * n * 60);
        }
    };
}

test "duration" {
    const sr = 48000;
    const dur = duration(sr);

    try expectEqual(sr, dur.sec(1));
    try expectEqual(sr / 2, dur.sec(0.5));
    try expectEqual(sr / 1000, dur.msec(1));
    try expectEqual(sr * 60, dur.min(1));
}
