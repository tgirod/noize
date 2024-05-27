const std = @import("std");
const testing = std.testing;
const ee = testing.expectEqual;

const b = @import("./base.zig");

pub fn Comb(comptime srate: f32, comptime delay: f32, comptime gain: f32) type {
    const Feedback = b.Mem(srate, delay).seq(b.MulAdd(gain, 0));
    const Forward = b.Id(2).merge(b.Id(1)).split(b.Id(2));
    return Forward.rec(Feedback);
}
