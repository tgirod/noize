const n = @import("./root.zig");
const std = @import("std");

const srate = 48000;

const Feedback = n.Const(.{0.1})
    .seq(n.Sin(srate))
    .seq(n.Range(0.1, 1.0))
    .seq(n.Delay(48000, 1));

const Forward = n.Id(2)
    .merge(n.Id(1))
    .split(n.Id(2));

const Loopback = Forward.rec(Feedback);

const Comb = n.Id(2)
    .merge(n.Mem(srate, 0.5))
    .seq(n.Comb(srate, 1.0 / 880.0, 0.9))
    .split(n.Id(2));

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
