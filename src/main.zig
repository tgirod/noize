const std = @import("std");
const n = @import("noize.zig");
const jack = @import("jack.zig");

var client: jack.Client = undefined;
var out: jack.Port = undefined;

pub fn main() !void {
    client = try jack.Client.init("noize");
    defer client.deinit();

    try client.setProcessCallback(&processCallback);

    out = try client.outputAudioPort("out");
    defer out.deinit();

    try client.activate();

    std.debug.print("sleeping\n", .{});
    std.time.sleep(std.time.ns_per_s);
    std.debug.print("\nwaking up\n", .{});

    try client.deactivate();
}

fn processCallback(nframes: u32, arg: ?*anyopaque) callconv(.C) c_int {
    _ = arg;
    const buf = out.getBuffer(nframes);
    std.debug.print("{any}\n", .{buf});
    return 0;
}

// pub fn main() !void {
//     const Node = n.Sin();
//     var node = Node{};

//     for (0..480) |i| {
//         const out = node.eval(.{@as(f64, @floatFromInt(i)) * 10});
//         std.debug.print("{any}\n", .{out[0]});
//     }
// }
