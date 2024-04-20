const std = @import("std");
const testing = std.testing;
const ee = testing.expectEqual;

const node = @import("./node.zig");

var lfsr: u16 = 0xACE1;

/// pseudo random number generator
pub fn rand() f32 {
    lfsr ^= lfsr >> 7;
    lfsr ^= lfsr << 9;
    lfsr ^= lfsr >> 13;
    const max: f32 = @floatFromInt((1 << 16) - 2);
    return @as(f32, @floatFromInt(lfsr - 1)) / max;
}

/// Perlin noise (single octave)
pub fn Perlin(comptime srate: f32) type {
    const step: f32 = 1 / srate;

    return struct {
        const Self = @This();
        pub usingnamespace node.NodeInterface(Self);

        pub const in = 1; // frequency
        pub const out = 1; // signal

        phase: f32 = 0,
        loSlope: f32 = rand() * 2 - 1,
        hiSlope: f32 = rand() * 2 - 1,

        pub fn eval(self: *Self, input: [in]f32) [out]f32 {
            const d = self.phase;
            _ = input;
            const loPos = self.loSlope * d;
            const hiPos = -self.hiSlope * (1 - d);
            const u = d * d * (3.0 - 2.0 * d);
            const output = (loPos * (1 - u)) + (hiPos * u);
            self.phase += step;
            if (self.phase >= 1.0) {
                self.phase -= 1.0;
                self.loSlope = self.hiSlope;
                self.hiSlope = rand() * 2 - 1;
            }

            return .{output};
        }
    };
}
