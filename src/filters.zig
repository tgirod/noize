const std = @import("std");
const testing = std.testing;
const ee = testing.expectEqual;

const n = @import("root.zig");

pub fn Comb(comptime srate: f32, comptime delay: f32, comptime gain: f32) type {
    const Feedback = n.Seq(n.Mem(srate, delay), n.MulAdd(gain, 0));
    const Forward = n.Seq(n.Merge(2, 1), n.Split(1, 2));
    return n.Rec(Forward, Feedback);
}

// pub fn AllPass(comptime srate: f32, comptime delay: f32, comptime gain: f32) type {
//     const NegativeForward = n.MulAdd(-gain);
//     const Feedback = Comb(srate, delay, gain);
//     const Par = n.Par(NegativeForward, Feedback);
//     return n.MergeOut(n.SplitIn(Par, 2), 2);
// }
