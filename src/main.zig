const std = @import("std");
const jack = @import("jack.zig");

const n = @import("noize.zig");

var client: jack.Client = undefined;
var step: f32 = undefined;

pub fn main() !void {
    client = try jack.Client.init(std.heap.page_allocator, "noize");
    defer client.deinit();

    step = 1 / @as(f32, @floatFromInt(client.getSampleRate()));

    try client.setProcessCallback(&processCallback);

    try client.registerPort("in", .AudioInput);
    try client.registerPort("out", .AudioOutput);
    try client.activate();
    defer client.deactivate() catch {};

    try client.connect();

    while (true) {
        std.time.sleep(std.time.ns_per_s);
    }
}

const Lfo = n.SeqN(&[_]type{
    n.Const(f32, 0.2),
    n.Sin(),
    n.MulAdd(f32, 20000, 20000),
    n.FloatToInt(f32, usize),
});

const VarDelay = n.Seq(
    n.Par(n.Id(f32), Lfo),
    n.Delay(f32, 48000),
);

var node = n.Rec(
    n.Mix(f32, 0.3),
    VarDelay,
){};

fn processCallback(nframes: u32, arg: ?*anyopaque) callconv(.C) c_int {
    _ = arg;
    const in_buf = client.inputBuffer(0, nframes);
    const out_buf = client.outputBuffer(0, nframes);

    for (in_buf, out_buf) |*i, *o| {
        const out = node.eval(step, .{i.*});
        o.* = out[0];
    }
    return 0;
}
