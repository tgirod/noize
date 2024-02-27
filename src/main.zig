const n = @import("./root.zig");
const std = @import("std");

const srate = 48000;

const Root = n.Id(2);

var back: n.Backend(Root) = undefined;

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
