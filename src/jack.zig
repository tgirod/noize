const std = @import("std");
const testing = std.testing;
const c = @cImport({
    @cInclude("jack/jack.h");
});

pub const ProcessCallback = ?*const fn (c.jack_nframes_t, ?*anyopaque) callconv(.C) c_int;

pub const PortType = enum(c_ulong) {
    AudioInput = c.JackPortIsInput,
    AudioOutput = c.JackPortIsOutput,
};

pub const Client = struct {
    client: ?*c.jack_client_t = undefined,
    status: c.jack_status_t = undefined,
    inputs: std.ArrayList(?*c.jack_port_t) = undefined,
    outputs: std.ArrayList(?*c.jack_port_t) = undefined,

    /// open new jack client
    pub fn init(allo: std.mem.Allocator, name: [*]const u8) !Client {
        var result = Client{};
        result.client = c.jack_client_open(name, c.JackNullOption, &result.status) orelse null;
        if (result.client == null) {
            return error.CannotOpenClient;
        }
        result.inputs = std.ArrayList(?*c.jack_port_t).init(allo);
        result.outputs = std.ArrayList(?*c.jack_port_t).init(allo);
        return result;
    }

    /// close jack client
    pub fn deinit(self: *Client) void {
        for (self.inputs.items) |p| {
            _ = c.jack_port_unregister(self.client, p);
        }
        self.inputs.deinit();

        for (self.outputs.items) |p| {
            _ = c.jack_port_unregister(self.client, p);
        }
        self.outputs.deinit();

        _ = c.jack_client_close(self.client);
    }

    /// return samplerate
    pub fn getSampleRate(self: *Client) u32 {
        return c.jack_get_sample_rate(self.client);
    }

    /// activate jack client
    pub fn activate(self: *Client) !void {
        if (c.jack_activate(self.client) != 0)
            return error.CannotActivateClient;
    }

    /// deactivate jack client
    pub fn deactivate(self: *Client) !void {
        if (c.jack_deactivate(self.client) != 0)
            return error.CannotDeactivateClient;
    }

    pub fn setProcessCallback(self: *Client, cb: ProcessCallback) !void {
        if (c.jack_set_process_callback(self.client, cb, null) != 0) {
            return error.CannotSetCallback;
        }
    }

    pub fn registerPort(self: *Client, name: [*]const u8, portType: PortType) !void {
        const port = c.jack_port_register(self.client, name, c.JACK_DEFAULT_AUDIO_TYPE, @intFromEnum(portType), 0) orelse null;
        if (port == null) {
            return error.CannotRegisterPort;
        }

        _ = switch (portType) {
            .AudioInput => try self.inputs.append(port),
            .AudioOutput => try self.outputs.append(port),
        };
    }

    /// connect ports to default physical inputs and outputs
    pub fn connect(self: *Client) !void {
        const sources = c.jack_get_ports(self.client, "", "", c.JackPortIsPhysical | c.JackPortIsOutput);
        var index: usize = 0;
        while (index < self.inputs.items.len and sources[index] != 0) {
            const source = sources[index];
            const target = c.jack_port_name(self.inputs.items[index]);
            if (c.jack_connect(self.client, source, target) != 0) {
                return error.CannotConnect;
            }
            index += 1;
        }

        const targets = c.jack_get_ports(self.client, "", "", c.JackPortIsPhysical | c.JackPortIsInput);
        index = 0;
        while (index < self.outputs.items.len and targets[index] != 0) {
            const source = c.jack_port_name(self.outputs.items[index]);
            const target = targets[index];
            if (c.jack_connect(self.client, source, target) != 0) {
                return error.CannotConnect;
            }
            index += 1;
        }
    }

    pub fn inputBuffer(self: *Client, index: usize, nframes: u32) []f32 {
        const buf = c.jack_port_get_buffer(self.inputs.items[index], nframes);
        return @as([*]f32, @ptrCast(@alignCast(buf)))[0..nframes];
    }

    pub fn outputBuffer(self: *Client, index: usize, nframes: u32) []f32 {
        const buf = c.jack_port_get_buffer(self.outputs.items[index], nframes);
        return @as([*]f32, @ptrCast(@alignCast(buf)))[0..nframes];
    }
};
