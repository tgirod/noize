const std = @import("std");
const testing = std.testing;
const Tuple = std.meta.Tuple;
const c = @cImport({
    @cInclude("jack/jack.h");
});

pub fn Client(RootNode: type) type {
    const I = RootNode.Input.len;
    const O = RootNode.Output.len;
    comptime var input_names: [I][*]const u8 = undefined;
    inline for (0..I) |i|
        input_names[i] = std.fmt.comptimePrint("in{d}", .{i});

    comptime var output_names: [O][*]const u8 = undefined;
    inline for (0..O) |i|
        output_names[i] = std.fmt.comptimePrint("out{d}", .{i});

    return struct {
        root: RootNode = undefined,
        client: *c.jack_client_t = undefined,
        status: c.jack_status_t = undefined,
        inputs: [I]?*c.jack_port_t = undefined,
        outputs: [O]?*c.jack_port_t = undefined,

        const Self = @This();

        fn processCallback(nframes: u32, arg: ?*anyopaque) callconv(.C) c_int {
            const client: *Self = @alignCast(@ptrCast(arg));
            const input = client.inputBuffers(nframes);
            const output = client.outputBuffers(nframes);
            for (0..nframes) |i| {
                const In = Tuple(&RootNode.Input);
                const Out = Tuple(&RootNode.Output);
                var in: In = undefined;
                inline for (0..input.len) |j| {
                    in[j] = input[j][i];
                }
                const out: Out = client.root.eval(in);
                inline for (0..output.len) |j| {
                    output[j][i] = out[j];
                }
            }
            return 0;
        }

        /// open new jack client
        pub fn init(self: *Self, name: [*]const u8) !void {
            self.client = c.jack_client_open(name, c.JackNullOption, &self.status) orelse return error.CannotOpenClient;

            // register input ports
            for (0..I) |i| {
                self.inputs[i] = c.jack_port_register(self.client, input_names[i], c.JACK_DEFAULT_AUDIO_TYPE, c.JackPortIsInput, 0) orelse null;
                if (self.inputs[i] == null) return error.CannotRegisterPort;
            }

            // register output ports
            for (0..O) |i| {
                self.outputs[i] = c.jack_port_register(self.client, output_names[i], c.JACK_DEFAULT_AUDIO_TYPE, c.JackPortIsOutput, 0) orelse null;
                if (self.outputs[i] == null) return error.CannotRegisterPort;
            }

            if (c.jack_set_process_callback(self.client, &processCallback, self) != 0) {
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
                std.debug.print("connecting : {s} --> {s}\n", .{ source.?, target });
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
                std.debug.print("connecting : {s} --> {s}\n", .{ source, target.? });
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
