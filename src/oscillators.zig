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
