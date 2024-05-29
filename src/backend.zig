const std = @import("std");
const testing = std.testing;
const c = @cImport({
    @cInclude("jack/jack.h");
});

const tup = @import("tuple.zig");

pub fn Backend(RootNode: type) type {
    const in = tup.len(RootNode.Input);
    const out = tup.len(RootNode.Output);

    // TODO assert inputs and outputs are f32

    comptime var input_names: [in][*]const u8 = undefined;
    inline for (0..in) |i|
        input_names[i] = std.fmt.comptimePrint("in{d}", .{i});

    comptime var output_names: [out][*]const u8 = undefined;
    inline for (0..out) |i|
        output_names[i] = std.fmt.comptimePrint("out{d}", .{i});

    return struct {
        client: *c.jack_client_t = undefined,
        status: c.jack_status_t = undefined,
        inputs: [in]*c.jack_port_t = undefined,
        outputs: [out]*c.jack_port_t = undefined,

        root: RootNode = undefined,
        const Self = @This();

        pub fn init(self: *Self, name: [*]const u8) !void {
            self.root.init();

            self.client = c.jack_client_open(
                name,
                c.JackNullOption,
                &self.status,
            ) orelse return error.CannotOpenClient;

            // register input ports
            for (0..in) |i| {
                self.inputs[i] = c.jack_port_register(
                    self.client,
                    input_names[i],
                    c.JACK_DEFAULT_AUDIO_TYPE,
                    c.JackPortIsInput,
                    0,
                ) orelse return error.CannotRegisterInputPort;
            }

            // register output ports
            for (0..out) |i| {
                self.outputs[i] = c.jack_port_register(
                    self.client,
                    output_names[i],
                    c.JACK_DEFAULT_AUDIO_TYPE,
                    c.JackPortIsOutput,
                    0,
                ) orelse return error.CannotRegisterOutputPort;
            }

            // set process callback
            if (c.jack_set_process_callback(self.client, &callback, self) != 0) {
                return error.CannotSetCallback;
            }
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

        /// close jack client
        pub fn deinit(self: *Self) void {
            for (self.inputs) |p| {
                if (c.jack_port_unregister(self.client, p) != 0) {
                    @panic("cannot unregister input port");
                }
            }

            for (self.outputs) |p| {
                if (c.jack_port_unregister(self.client, p) != 0) {
                    @panic("cannot unregister output port");
                }
            }

            if (c.jack_client_close(self.client) != 0) {
                @panic("cannot close client");
            }
        }

        fn callback(nframes: c.jack_nframes_t, data: ?*anyopaque) callconv(.C) c_int {
            // retrieve pointer to client from data
            const self: *Self = @alignCast(@ptrCast(data));
            // get input and output buffers
            var input_buffers: [in][*]f32 = undefined;
            var output_buffers: [out][*]f32 = undefined;
            for (0..in) |i| {
                input_buffers[i] = @alignCast(@ptrCast(c.jack_port_get_buffer(self.inputs[i], nframes)));
            }
            for (0..out) |o| {
                output_buffers[o] = @alignCast(@ptrCast(c.jack_port_get_buffer(self.outputs[o], nframes)));
            }

            // evaluate the frames
            var input: RootNode.Input = undefined;
            var output: RootNode.Output = undefined;
            for (0..nframes) |frame| {
                // extract current frame from input buffers
                inline for (0..in) |channel| {
                    input[channel] = input_buffers[channel][frame];
                }
                // evaluate the current frame and copy the result into the output buffers
                output = self.root.eval(input);
                inline for (0..out) |channel| {
                    output_buffers[channel][frame] = output[channel];
                }
            }
            return 0;
        }
    };
}
