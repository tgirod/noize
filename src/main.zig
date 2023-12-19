const std = @import("std");
const jack = @import("jack.zig");

const n = @import("noize.zig");

const Lfo = n.SeqN(&[_]type{
    n.Const(f32, 0.2),
    n.Sin(),
    n.Rescale(f32, -1, 1, 10, 48000),
    n.FloatToInt(f32, usize),
});

const VarDelay = n.Seq(
    n.Par(n.Id(f32), Lfo),
    n.Delay(f32, 48000),
);

const Loopback = n.Rec(
    n.Mix(f32, 0.3),
    VarDelay,
);

var root = n.Noize(Loopback){};

fn processCallback(nframes: u32, arg: ?*anyopaque) callconv(.C) c_int {
    _ = arg;
    const inputs = client.inputBuffers(nframes);
    const outputs = client.outputBuffers(nframes);
    root.eval(nframes, inputs, outputs);
    return 0;
}

var client: jack.Client(1, 1) = undefined;

pub fn main() !void {
    try client.init("noize", &processCallback);
    defer client.deinit();

    try client.activate();
    defer client.deactivate() catch {};

    try client.connect();

    n.init(client.samplerate());

    while (true) {
        std.time.sleep(std.time.ns_per_s);
    }
}
