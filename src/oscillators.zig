const std = @import("std");
const tau = std.math.tau;
const ee = std.testing.expectEqual;

/// sinewave at the given frequency
pub fn Sin(srate: f32) type {
    const step: f32 = 1 / srate;

    return struct {
        pub const in = 1;
        pub const out = 1;

        phase: f32 = 0,

        pub fn eval(self: *@This(), input: [in]f32) [out]f32 {
            const v = @sin(self.phase);
            const freq = input[0];
            self.phase = @mod(self.phase + freq * step * tau, tau);
            return .{v};
        }
    };
}

/// generate signal based on a wavetable
pub fn Wavetable(srate: f32, buffer: []f32) type {
    const step: f32 = 1 / srate;

    return struct {
        pub const in = 1; // frequency
        pub const out = 1; // signal

        phase: f32 = 0,

        pub fn eval(self: *@This(), input: [in]f32) [out]f32 {
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
