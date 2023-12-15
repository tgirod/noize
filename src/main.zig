const std = @import("std");
const n = @import("noize.zig");
const jack = @import("jack.zig");

var client: jack.Client = undefined;
var out: jack.Port = undefined;
var step: f32 = undefined;

const Node = n.SeqN(&[_]type{
    n.Dup(n.Sin(), 2),
    // n.Add(f32),
});

var node = Node{};

var now: f32 = 0;

pub fn main() !void {
    client = try jack.Client.init(std.heap.page_allocator, "noize");
    defer client.deinit();

    step = 1 / @as(f32, @floatFromInt(client.getSampleRate()));

    try client.setProcessCallback(&processCallback);

    try client.registerPort("out0", .AudioOutput);
    try client.registerPort("out1", .AudioOutput);
    try client.activate();
    defer client.deactivate() catch {};

    try client.connect();

    std.debug.print("sleeping\n", .{});
    std.time.sleep(5 * std.time.ns_per_s);
    std.debug.print("\nwaking up\n", .{});
}

fn processCallback(nframes: u32, arg: ?*anyopaque) callconv(.C) c_int {
    _ = arg;
    const buf0 = client.outputBuffer(0, nframes);
    const buf1 = client.outputBuffer(1, nframes);
    for (buf0, buf1) |*b0, *b1| {
        const frame = node.eval(step, .{ 400 + now * 10, 400 + now * 15 });
        b0.* = frame[0];
        b1.* = frame[1];
        now += step;
    }
    return 0;
}
