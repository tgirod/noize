const std = @import("std");
const n = @import("noize.zig");
const jack = @import("jack.zig");

var client: jack.Client = undefined;
var out: jack.Port = undefined;
var step: f32 = undefined;

pub fn main() !void {
    client = try jack.Client.init("noize");
    defer client.deinit();

    step = 1 / @as(f32, @floatFromInt(client.getSampleRate()));

    try client.setProcessCallback(&processCallback);

    out = try client.outputAudioPort("out");
    defer out.deinit();

    try client.activate();

    std.debug.print("sleeping\n", .{});
    std.time.sleep(10 * std.time.ns_per_s);
    std.debug.print("\nwaking up\n", .{});

    try client.deactivate();
}

const Node = n.SeqN(&[_]type{
    n.Par(n.Const(f32, 440), n.Const(f32, 800)),
    n.Dup(n.Sin(), 2),
    n.Add(f32),
});

var node = Node{};

fn processCallback(nframes: u32, arg: ?*anyopaque) callconv(.C) c_int {
    _ = arg;
    const buf = out.getBuffer(nframes);
    for (buf) |*i| {
        i.* = node.eval(step, .{})[0];
    }
    return 0;
}
