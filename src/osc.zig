const std = @import("std");
const testing = std.testing;
const ee = testing.expectEqual;
const node = @import("./node.zig");

/// sinewave at the given frequency
pub fn Sin(comptime srate: f32) type {
    const step: f32 = 1 / srate;
    const tau = std.math.tau;

    return struct {
        const Self = @This();
        pub usingnamespace node.NodeInterface(Self);

        pub const in = 1; // frequency
        pub const out = 1; // output

        phase: f32 = 0,

        pub fn eval(self: *Self, input: [in]f32) [out]f32 {
            const v = @sin(self.phase);
            const freq = input[0];
            self.phase = @mod(self.phase + freq * step * tau, tau);
            return .{v};
        }
    };
}

/// generate signal based on a wavetable
pub fn Wavetable(comptime srate: f32, comptime buffer: []f32) type {
    const step: f32 = 1 / srate;

    return struct {
        const Self = @This();
        pub usingnamespace node.NodeInterface(Self);

        pub const in = 1; // frequency
        pub const out = 1; // signal

        phase: f32 = 0,

        pub fn eval(self: *Self, input: [in]f32) [out]f32 {
            // linear interpolation
            const pos = self.phase * buffer.len;
            const idx: usize = @intFromFloat(pos);
            const a = buffer[idx];
            const b = buffer[(idx + 1) % buffer.len];
            const t = @mod(pos, 1);
            const value = std.math.lerp(a, b, t);
            // move phase forward
            const freq = input[0];
            self.phase = @mod(self.phase + freq * step, 1);
            return .{value};
        }
    };
}
