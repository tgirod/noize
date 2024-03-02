const std = @import("std");
const testing = std.testing;
const ee = testing.expectEqual;

const n = @import("root.zig");

pub fn Comb(comptime srate: f32, comptime delay: f32, comptime gain: f32) type {
    const Feedback = n.Seq(n.Mem(srate, delay), n.MulAdd(gain, 0));
    const Forward = n.Fork(n.Sum());
    return n.Rec(Forward, Feedback);
}

// pub fn AllPass(comptime srate: f32, comptime delay: f32, comptime gain: f32) type {
//     const Input = n.Id(1);
//     _ = Input;
//     const Forward = n.MulAdd(-gain);
//     const Feedback = Comb(srate, delay, gain);
//     const Main = n.Par(Forward, Feedback);
//     _ = Main;
//     n.Split(Input, Main)
// }
