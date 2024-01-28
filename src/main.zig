const std = @import("std");
const jack = @import("jack.zig");

const n = @import("noize.zig").Noize(48000);

const Lfo = n.SeqN(&[_]type{
    n.Const(f32, 0.2),
    n.Sin(),
    n.MulAdd(10000, 24000),
    n.FloatToInt(f32, usize),
});

const VarDelay = n.Seq(
    n.Par(n.Id(f32), Lfo),
    n.Delay(f32, 48000),
);

const Loopback = n.Rec(
    n.Fork(n.Sum(f32)),
    VarDelay,
);

//

const Root = n.Root(n.Stereo(Loopback));
var root = Root{};

fn processCallback(nframes: u32, arg: ?*anyopaque) callconv(.C) c_int {
    _ = arg;
    const input = client.inputBuffers(nframes);
    const output = client.outputBuffers(nframes);
    root.eval(nframes, input, output);
    return 0;
}

var client: jack.Client(1, 2) = undefined;

pub fn main() !void {
    try client.init("noize", &processCallback);
    defer client.deinit();
    std.debug.print("init ok\n", .{});

    try client.activate();
    defer client.deactivate() catch {};
    std.debug.print("activate ok\n", .{});

    try client.connect();
    std.debug.print("connect ok\n", .{});

    while (true) {
        std.time.sleep(std.time.ns_per_s);
    }
}
