const std = @import("std");
const c = @cImport({
    @cInclude("jack/jack.h");
});

pub const Error = error{
    ClientOpenFailed,
    PortRegisterFailed,
};

// FIXME ugly hack
const in_ports = [_][*c]const u8{ "in1", "in2", "in3", "in4", "in5", "in6", "in7", "in8" };
const out_ports = [_][*c]const u8{ "out1", "out2", "out3", "out4", "out5", "out6", "out7", "out8" };

pub const ProcessCallback = *const fn (nframes: u32, *Client) u32;

pub const Client = struct {
    allo: std.mem.Allocator = undefined,
    status: c.jack_status_t = undefined,
    client: ?*c.jack_client_t = undefined,
    in_ports: []?*c.jack_port_t = undefined,
    out_ports: []?*c.jack_port_t = undefined,
    process: ProcessCallback = undefined,

    const Self = @This();

    fn processCallback(nframes: c.jack_nframes_t, arg: ?*anyopaque) c_int {
        _ = arg;
        _ = nframes;
    }

    pub fn init(allo: std.mem.Allocator, name: [*c]const u8, input: usize, output: usize, process: ProcessCallback) !Self {
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
        _ = c.jack_set_process_callback(client.client, &client.processCallback, &client); // FIXME

        return client;
    }

    pub fn deinit(self: *Self) void {
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

    pub fn activate(self: *Self) void {
        _ = c.jack_activate(self.client); // FIXME
    }

    pub fn deactivate(self: *Self) void {
        _ = c.jack_deactivate(self.client); // FIXME
    }
};
