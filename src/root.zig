const std = @import("std");
const testing = std.testing;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const Tuple = std.meta.Tuple;

test "test dispatch" {
    testing.refAllDecls(@This());
}

/// check if two tuple types are identical
fn eq(comptime A: type, comptime B: type) bool {
    // TODO check A and B are tuples
    const fa = std.meta.fields(A);
    const fb = std.meta.fields(B);
    if (fa.len != fb.len) {
        return false;
    }
    inline for (fa, fb) |a, b| {
        if (a.type != b.type) {
            return false;
        }
    }
    return true;
}

test "eq" {
    const A = struct { f32, u8 };
    const B = struct { f32, u8 };
    const C = struct { u8, f32 };
    const D = struct { u8 };
    try expect(eq(A, A));
    try expect(eq(A, B));
    try expect(!eq(A, C));
    try expect(!eq(A, D));
}

/// returns the length of a tuple type
fn len(comptime A: type) usize {
    return std.meta.fields(A).len;
}

test "len" {
    const A = struct { u8, f32 };
    const B = struct { u8 };
    try expectEqual(2, len(A));
    try expectEqual(1, len(B));
}

/// concatenate two tuple types
fn Join(A: type, B: type) type {
    const a: A = undefined;
    const b: B = undefined;
    return @TypeOf(a ++ b);
}

test "Join" {
    const A = struct { f32 = 0 };
    const B = struct { u8 = 0, bool = false };
    const AB = Join(A, B);
    const ab: AB = undefined;
    try expectEqual(3, ab.len);
    try expectEqual(f32, @TypeOf(ab[0]));
    try expectEqual(u8, @TypeOf(ab[1]));
    try expectEqual(bool, @TypeOf(ab[2]));
}

/// split a tuple type in two at pivot point
fn Split(T: type, pivot: usize) type {
    const fields = std.meta.fields(T);
    std.debug.assert(pivot <= fields.len);
    var types_a: [pivot]type = undefined;
    var types_b: [fields.len - pivot]type = undefined;
    for (fields, 0..) |f, i| {
        if (i < pivot) {
            types_a[i] = f.type;
        } else {
            types_b[i - pivot] = f.type;
        }
    }
    const Tuple_a = Tuple(&types_a);
    const Tuple_b = Tuple(&types_b);
    return struct { Tuple_a, Tuple_b };
}

test "Split" {
    const AB = Split(struct { f32, u8, bool }, 1);
    const ab: AB = undefined;
    try expectEqual(1, ab[0].len);
    try expectEqual(2, ab[1].len);
    try expectEqual(f32, @TypeOf(ab[0][0]));
    try expectEqual(u8, @TypeOf(ab[1][0]));
    try expectEqual(bool, @TypeOf(ab[1][1]));
}

/// split a tuple at pivot point
fn split(tuple: anytype, comptime pivot: usize) Split(@TypeOf(tuple), pivot) {
    var sp: Split(@TypeOf(tuple), pivot) = undefined;
    inline for (tuple, 0..) |value, index| {
        if (index < pivot) {
            sp[0][index] = value;
        } else {
            sp[1][index - pivot] = value;
        }
    }
    return sp;
}

test "split" {
    const tuple: struct { u8, f32, bool } = .{ 1, 2, false };
    const sp = split(tuple, 1);
    try expectEqual(@as(u8, 1), sp[0][0]);
    try expectEqual(@as(f32, 2), sp[1][0]);
    try expectEqual(@as(bool, false), sp[1][1]);
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
    };
}

/// parallel operator : combine A and B in parallel
fn Par(A: type, B: type) type {
    return struct {
        pub usingnamespace NodeInterface(Self);
        const Self = @This();

        pub const Input = Join(A.Input, B.Input);
        pub const Output = Join(A.Output, B.Output);

        a: A = undefined,
        b: B = undefined,

        pub fn init(self: *Self) void {
            self.a.init();
            self.b.init();
        }

        pub fn eval(self: *Self, input: Input) Output {
            const sp = split(input, len(A.Input));
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
fn Seq(comptime A: type, comptime B: type) type {
    return struct {
        pub usingnamespace NodeInterface(Self);
        const Self = @This();

        const diff = @as(comptime_int, len(A.Output)) - @as(comptime_int, len(B.Input));

        pub const Input = init: {
            if (diff < 0) {
                // add spare inputs of B
                const sp: Split(B.Input, len(A.Output)) = undefined;
                std.debug.assert(eq(@TypeOf(sp[0]), A.Output));
                break :init Join(A.Input, @TypeOf(sp[1]));
            } else {
                break :init A.Input;
            }
        };

        pub const Output = init: {
            if (diff > 0) {
                // add spare outputs of A
                const sp: Split(A.Output, len(B.Input)) = undefined;
                std.debug.assert(eq(@TypeOf(sp[0]), B.Input));
                break :init Join(B.Output, @TypeOf(sp[1]));
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
                const sp = split(input, len(A.Input));
                const input_a: A.Input = sp[0];
                const spare = sp[1];
                const output_a: A.Output = self.a.eval(input_a);
                const input_b: B.Input = output_a ++ spare;
                return self.b.eval(input_b);
            } else if (diff > 0) {
                // spare outputs of A are routed to the main output
                const output_a: A.Output = self.a.eval(input);
                const sp = split(output_a, len(B.Input));
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
    try expectEqual(2, len(N.Input));
    try expectEqual(2, len(N.Output));
    var n = N{};
    n.init();
    try expectEqual(.{ 23, false }, n.eval(.{ 23, false }));
}

test "seq - spare outputs" {
    const A = Id(u8).par(Id(bool));
    const B = Id(u8);
    const N = A.seq(B);
    try expectEqual(2, len(N.Input));
    try expectEqual(2, len(N.Output));
    var n = N{};
    n.init();
    try expectEqual(.{ 23, false }, n.eval(.{ 23, false }));
    try expectEqual(2, len(N.Output));
}

/// recursive operator : loop A --> B --> A
/// A --> B is delayed one sample to avoid infinite loop
/// spare inputs of A are exposed as inputs of Rec
/// spare outputs of A are exposed as outputs of Rec
fn Rec(comptime A: type, comptime B: type) type {
    std.debug.assert(len(B.Input) < len(A.Output));
    std.debug.assert(len(B.Output) < len(A.Input));

    const split_input: Split(A.Input, len(B.Output)) = undefined;
    std.debug.assert(eq(B.Output, @TypeOf(split_input[0])));

    const split_output: Split(A.Output, len(B.Input)) = undefined;
    std.debug.assert(eq(B.Input, @TypeOf(split_output[0])));

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
            const sp = split(output_a, len(B.Input));
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
    try expectEqual(1, len(N.Input));
    try expectEqual(1, len(N.Output));

    var n: N = undefined;
    n.init();
    try expectEqual(.{1}, n.eval(.{1}));
    try expectEqual(.{1}, n.mem);
    try expectEqual(.{2}, n.eval(.{1}));
}

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
