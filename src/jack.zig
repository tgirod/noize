const std = @import("std");
const testing = std.testing;
const c = @cImport({
    @cInclude("jack/jack.h");
});

pub const ProcessCallback = ?*const fn (c.jack_nframes_t, ?*anyopaque) callconv(.C) c_int;

pub const Client = struct {
    client: ?*c.jack_client_t = undefined,
    status: c.jack_status_t = undefined,

    /// open new jack client
    pub fn init(name: [*]const u8) !Client {
        var result = Client{};
        result.client = c.jack_client_open(name, c.JackNullOption, &result.status) orelse null;
        if (result.client == null) {
            return error.CannotOpenClient;
        }

        return result;
    }

    /// close jack client
    pub fn deinit(self: *Client) void {
        _ = c.jack_client_close(self.client);
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

    /// register new input audio port
    pub fn inputAudioPort(self: *Client, name: [*]const u8) !Port {
        return Port.init(self, name, .AudioInput);
    }

    /// register new output audio port
    pub fn outputAudioPort(self: *Client, name: [*]const u8) !Port {
        return Port.init(self, name, .AudioOutput);
    }

    /// return samplerate
    pub fn getSampleRate(self: *Client) u32 {
        return c.jack_get_sample_rate(self.client);
    }
};

pub const PortType = enum {
    AudioInput,
    AudioOutput,
    MidiInput,
    MidiOutput,
};

pub const Port = struct {
    client: ?*c.jack_client_t,
    port: ?*c.jack_port_t,

    pub fn init(client: *Client, name: [*]const u8, portType: PortType) !Port {
        const _type = switch (portType) {
            .AudioInput, .AudioOutput => c.JACK_DEFAULT_AUDIO_TYPE,
            .MidiInput, .MidiOutput => c.JACK_DEFAULT_MIDI_TYPE,
        };

        const flag: c_ulong = switch (portType) {
            .AudioInput, .MidiInput => c.JackPortIsInput,
            .AudioOutput, .MidiOutput => c.JackPortIsOutput,
        };

        const port = c.jack_port_register(client.client, name, _type, flag, 0) orelse null;
        if (port == null) {
            return error.CannotRegisterPort;
        }

        return Port{
            .client = client.client,
            .port = port,
        };
    }

    pub fn deinit(self: *Port) void {
        _ = c.jack_port_unregister(self.client, self.port);
    }

    pub fn getBuffer(self: *Port, nframes: u32) []f32 {
        const buf = c.jack_port_get_buffer(self.port, nframes);
        return @as([*]f32, @ptrCast(@alignCast(buf)))[0..nframes];
    }
};
