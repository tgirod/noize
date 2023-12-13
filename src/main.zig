const std = @import("std");
const n = @import("noize.zig");
const c = @cImport({
    @cInclude("jack/jack.h");
});

const Error = error{
    ClientOpenFailed,
    PortRegisterFailed,
};

// FIXME ugly hack
const in_ports = [_][*c]const u8{ "in1", "in2", "in3", "in4", "in5", "in6", "in7", "in8" };
const out_ports = [_][*c]const u8{ "out1", "out2", "out3", "out4", "out5", "out6", "out7", "out8" };

// type signature of jack process callback
pub const ProcessCallback = c.JackProcessCallback;

// pub fn Client(comptime inputs: usize, comptime outputs: usize) type {

pub const Client = struct {
    allo: std.mem.Allocator = undefined,
    status: c.jack_status_t = undefined,
    client: ?*c.jack_client_t = undefined,
    in_ports: []?*c.jack_port_t = undefined,
    out_ports: []?*c.jack_port_t = undefined,
    process: ProcessCallback = undefined,

    const Self = @This();

    fn init(allo: std.mem.Allocator, name: [*c]const u8, input: usize, output: usize, process: ProcessCallback) !Self {
        var client = Self{
            .allo = allo,
            .process = process,
            .in_ports = try allo.alloc(?*c.jack_port_t, input),
            .out_ports = try allo.alloc(?*c.jack_port_t, output),
        };
        errdefer allo.free(client.in_ports);
        errdefer allo.free(client.out_ports);

        // open client
        client.client = c.jack_client_open(name, c.JackNullOption, &client.status);
        if (client.client == null) {
            return Error.ClientOpenFailed;
        }
        errdefer _ = c.jack_client_close(client.client); // FIXME

        // open input ports
        const in = client.in_ports;
        for (0..in.len) |i| {
            in[i] = c.jack_port_register(client.client, in_ports[i], c.JACK_DEFAULT_AUDIO_TYPE, c.JackPortIsInput, 0) orelse null;
            if (in[i] == null) {
                return Error.PortRegisterFailed;
            }
            errdefer c.jack_port_unregister(client.client, in[i]);
        }

        // open output ports
        const out = client.out_ports;
        for (0..out.len) |i| {
            out[i] = c.jack_port_register(client.client, out_ports[i], c.JACK_DEFAULT_AUDIO_TYPE, c.JackPortIsOutput, 0) orelse null;
            if (out[i] == null) {
                return Error.PortRegisterFailed;
            }
            errdefer c.jack_port_unregister(client.client, out[i]);
        }

        // registrer process callback
        _ = c.jack_set_process_callback(client.client, client.process, &client); // FIXME

        return client;
    }

    fn deinit(self: *Self) void {
        for (self.in_ports) |p| {
            _ = c.jack_port_unregister(self.client, p); // FIXME
        }
        for (self.out_ports) |p| {
            _ = c.jack_port_unregister(self.client, p); // FIXME
        }
        _ = c.jack_client_close(self.client); // FIXME
        self.allo.free(self.in_ports);
        self.allo.free(self.out_ports);
    }

    fn activate(self: *Self) void {
        _ = c.jack_activate(self.client); // FIXME
    }

    fn deactivate(self: *Self) void {
        _ = c.jack_deactivate(self.client); // FIXME
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var client = try Client.init(allocator, "noize", 2, 1, processCallback);

    client.activate();
    defer client.deactivate();

    std.debug.print("sleeping\n", .{});
    std.time.sleep(std.time.ns_per_s);
    std.debug.print("\nwaking up\n", .{});
}

fn processCallback(nframes: c.jack_nframes_t, arg: ?*anyopaque) callconv(.C) c_int {
    const client: *Client = @ptrCast(@alignCast(arg));
    _ = client;
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
