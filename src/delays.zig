const std = @import("std");
const testing = std.testing;
const ee = testing.expectEqual;

/// delay line with a fixed size
pub fn Mem(comptime srate: f32, comptime length: f32) type {
    if (length <= 0) {
        @compileError("length <= 0");
    }

    const size: usize = @intFromFloat(srate * length);

    return struct {
        pub const in = 1;
        pub const out = 1;

        mem: [size]f32 = [1]f32{0} ** size,
        pos: usize = 0,

        pub inline fn eval(self: *@This(), input: [in]f32) [out]f32 {
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

/// delay line with dynamic length (maximum size defined at comptime)
pub fn Delay(comptime srate: f32, comptime maxLength: f32) type {
    if (maxLength <= 0) {
        @compileError("maxLength <= 0");
    }

    const size: usize = @intFromFloat(srate * maxLength);

    return struct {
        pub const in = 2; // length, input
        pub const out = 1; // output

        mem: [size]f32 = [1]f32{0} ** size,
        pos: usize = 0,

        pub inline fn eval(self: *@This(), input: [in]f32) [out]f32 {
            // write input into the memory
            self.mem[self.pos] = input[1];
            // compute delay length
            const length: i64 = @intFromFloat(input[0] * srate);
            const delay: usize = @intCast(@mod(@as(i64, @intCast(self.pos)) - length, size));
            // read `delay` samples before current position
            const read = self.mem[delay];
            // move position forward
            self.pos = (self.pos + 1) % size;
            return .{read};
        }
    };
}

test "Delay length 0" {
    const srate: f32 = 48000;
    const N = Delay(srate, 1.0);
    var n = N{};
    const input = [_]f32{ 1, 2, 3, 4, 5 };
    const expected = [_]f32{ 1, 2, 3, 4, 5 };
    for (input, expected) |in, exp| {
        const out = n.eval(.{ 0, in });
        try ee(exp, out[0]);
    }
}

test "Delay length 1 sample" {
    const srate: f32 = 48000;
    const N = Delay(srate, 1.0);
    var n = N{};
    const input = [_]f32{ 1, 2, 3, 4, 5 };
    const expected = [_]f32{ 0, 1, 2, 3, 4 };
    for (input, expected) |in, exp| {
        const out = n.eval(.{ 1 / srate, in });
        try ee(exp, out[0]);
    }
}

test "Delay length increasing" {
    const srate: f32 = 48000;
    const N = Delay(srate, 1.0);
    var n = N{};
    const input = [_]f32{ 0, 1, 2, 3, 4 };
    const expected = [_]f32{ 0, 0, 0, 0, 0 };
    for (input, expected) |in, exp| {
        const out = n.eval(.{ in / srate, in });
        try ee(exp, out[0]);
    }
}

pub fn MultiDelay(comptime srate: f32, comptime maxLength: f32, comptime taps: usize) type {
    if (maxLength <= 0) {
        @compileError("maxLength <= 0");
    }

    if (taps == 0) {
        @compileError("taps == 0");
    }

    const size: usize = @intFromFloat(srate * maxLength);

    return struct {
        pub const in = taps + 1; // lengths, input
        pub const out = taps; // outputs

        mem: [size]f32 = [1]f32{0} ** size,
        pos: usize = 0,

        pub inline fn eval(self: *@This(), input: [in]f32) [out]f32 {
            // write input into the memory
            self.mem[self.pos] = input[in - 1];

            var read: [taps]f32 = undefined;
            inline for (0..taps) |i| {
                // compute delay length
                const length: i64 = @intFromFloat(input[i] * srate);
                const delay: usize = @intCast(@mod(@as(i64, @intCast(self.pos)) - length, size));
                // read `delay` samples before current position
                read[i] = self.mem[delay];
            }
            // move position forward
            self.pos = (self.pos + 1) % size;
            return read;
        }
    };
}

test "MultiDelay" {
    const srate: f32 = 48000;
    const N = MultiDelay(srate, 1.0, 2);
    try ee(3, N.in);
    try ee(2, N.out);
    var n = N{};
    const input = [_]f32{ 1, 2, 3, 4, 5 };
    for (input) |in| {
        const out = n.eval([_]f32{ 0, 1 / srate, in });
        try ee([_]f32{ in, in - 1 }, out);
    }
}
