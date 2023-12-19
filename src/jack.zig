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

pub fn Client(comptime I: usize, comptime O: usize) type {
    comptime var input_names: [I][*]const u8 = undefined;
    inline for (0..I) |i|
        input_names[i] = std.fmt.comptimePrint("in{d}", .{i});

    comptime var output_names: [O][*]const u8 = undefined;
    inline for (0..O) |i|
        output_names[i] = std.fmt.comptimePrint("out{d}", .{i});

    return struct {
        client: ?*c.jack_client_t = undefined,
        status: c.jack_status_t = undefined,
        inputs: [I]?*c.jack_port_t = undefined,
        outputs: [O]?*c.jack_port_t = undefined,

        const Self = @This();

        /// open new jack client
        pub fn init(self: *Self, name: [*]const u8, cb: ProcessCallback) !void {
            self.client = c.jack_client_open(name, c.JackNullOption, &self.status) orelse null;
            if (self.client == null) {
                return error.CannotOpenClient;
            }

            // register input ports
            for (0..I) |i| {
                self.inputs[i] = c.jack_port_register(self.client, input_names[i], c.JACK_DEFAULT_AUDIO_TYPE, c.JackPortIsInput, 0) orelse null;
                if (self.inputs[i] == null) return error.CannotRegisterPort;
            }

            // register output ports
            for (0..I) |i| {
                self.outputs[i] = c.jack_port_register(self.client, output_names[i], c.JACK_DEFAULT_AUDIO_TYPE, c.JackPortIsOutput, 0) orelse null;
                if (self.outputs[i] == null) return error.CannotRegisterPort;
            }

            if (c.jack_set_process_callback(self.client, cb, null) != 0) {
                return error.CannotSetCallback;
            }
        }

        /// close jack client
        pub fn deinit(self: *Self) void {
            for (self.inputs) |p| {
                _ = c.jack_port_unregister(self.client, p);
            }

            for (self.outputs) |p| {
                _ = c.jack_port_unregister(self.client, p);
            }

            _ = c.jack_client_close(self.client);
        }

        /// return samplerate
        pub fn samplerate(self: *Self) u32 {
            return c.jack_get_sample_rate(self.client);
        }

        /// activate jack client
        pub fn activate(self: *Self) !void {
            if (c.jack_activate(self.client) != 0)
                return error.CannotActivateClient;
        }

        /// deactivate jack client
        pub fn deactivate(self: *Self) !void {
            if (c.jack_deactivate(self.client) != 0)
                return error.CannotDeactivateClient;
        }

        /// connect ports to default physical inputs and outputs
        pub fn connect(self: *Self) !void {
            const sources: [*:null]?[*:0]const u8 = c.jack_get_ports(self.client, "", "", c.JackPortIsPhysical | c.JackPortIsOutput);
            var index: usize = 0;
            while (index < self.inputs.len and sources[index] != null) {
                const source = sources[index];
                const target = c.jack_port_name(self.inputs[index]);
                if (c.jack_connect(self.client, source, target) != 0) {
                    return error.CannotConnect;
                }
                index += 1;
            }

            const targets = c.jack_get_ports(self.client, "", "", c.JackPortIsPhysical | c.JackPortIsInput);
            index = 0;
            while (index < self.outputs.len and targets[index] != null) {
                const source = c.jack_port_name(self.outputs[index]);
                const target = targets[index];
                if (c.jack_connect(self.client, source, target) != 0) {
                    return error.CannotConnect;
                }
                index += 1;
            }
        }

        pub fn inputBuffers(self: *Self, nframes: u32) [I][]f32 {
            var bufs: [I][]f32 = undefined;
            for (0..I) |i| {
                const buf = c.jack_port_get_buffer(self.inputs[i], nframes);
                bufs[i] = @as([*]f32, @ptrCast(@alignCast(buf)))[0..nframes];
            }
            return bufs;
        }

        pub fn outputBuffers(self: *Self, nframes: u32) [O][]f32 {
            var bufs: [O][]f32 = undefined;
            for (0..O) |i| {
                const buf = c.jack_port_get_buffer(self.outputs[i], nframes);
                bufs[i] = @as([*]f32, @ptrCast(@alignCast(buf)))[0..nframes];
            }
            return bufs;
        }
    };
}
