const std = @import("std");
const n = @import("noize.zig");
const jack = @import("jack.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var client = try jack.Client.init(allocator, "noize", 2, 1, processCallback);

    client.activate();
    defer client.deactivate();

    std.debug.print("sleeping\n", .{});
    std.time.sleep(std.time.ns_per_s);
    std.debug.print("\nwaking up\n", .{});
}

fn processCallback(nframes: u32, arg: *jack.Client) callconv(.C) c_int {
    _ = arg;
    // const client: *Client = @ptrCast(@alignCast(arg));
    // _ = client;
    std.debug.print("{any}\n", .{nframes});
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
