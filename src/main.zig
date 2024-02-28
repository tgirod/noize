const n = @import("./root.zig");
const std = @import("std");

const srate = 48000;

const Backward = n.Seq(
    n.Seq(n.Const(.{0.1}), n.Lfo(srate, 0.1, 1.0)),
    n.Delay(48000, 2),
);

const Sum = n.Merge(n.Id(2), n.Id(1));
const Forward = n.Fork(Sum);

const Loopback = n.Rec(
    Forward,
    Backward,
);

var back: n.Backend(n.Fork(Loopback)) = undefined;

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
