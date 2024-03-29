const n = @import("./root.zig");
const std = @import("std");

const srate = 48000;

const Backward = n.SeqN(&[_]type{
    n.Const(.{0.1}), // lfo frequency
    n.Sin(srate), // lfo
    n.Range(0.1, 1.0), // rescale lfo output to range [0.1, 1.0]
    n.Delay(48000, 1), // variable delay
});

const Forward = n.Seq(n.Merge(2, 1), n.Split(1, 2));

const Loopback = n.Rec(
    Forward,
    Backward,
);

const Comb = n.SeqN(&[_]type{
    n.Merge(2, 1),
    n.Mem(srate, 0.5),
    n.Comb(srate, 1.0 / 880.0, 0.9),
    n.Split(1, 2),
});

// var back: n.Backend(n.Fork(Loopback)) = undefined;
var back: n.Backend(Loopback) = undefined;

pub fn main() !void {
    try back.init("noize");
    defer back.deinit();

    try back.connect();
    try back.activate();
    defer back.deactivate();

    while (true) {
        std.time.sleep(std.time.ns_per_s);
    }
}
