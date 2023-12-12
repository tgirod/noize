const std = @import("std");
const n = @import("noize.zig");
const c = @cImport({
    @cInclude("jack/jack.h");
});

const Error = error{
    NoClient,
    NoInputPort,
    NoOutputPort,
    CannotActivate,
    CannotConnectInput,
    CannotConnectOutput,
};

const Client = struct {
    options: c.jack_options_t = c.JackNullOption,
    status: c.jack_status_t = undefined,
    client: *?c.jack_client_t = null,

    fn init(name: []const u8, inputs: usize, outputs: usize) !Client {
        _ = outputs;
        _ = inputs;
        _ = name;
    }
};

pub fn main() !void {
    const options = c.JackNullOption;
    var status: c.jack_status_t = undefined;

    // open client
    const client = c.jack_client_open("noize", options, &status);
    if (client == null) {
        return Error.NoClient;
    }
    defer _ = c.jack_client_close(client);
    _ = c.jack_set_process_callback(client, processCallback, null);
    _ = c.jack_on_shutdown(client, shutdownCallback, null);

    // register input and output ports
    const input_port = c.jack_port_register(client, "input", c.JACK_DEFAULT_AUDIO_TYPE, c.JackPortIsInput, 0);
    if (input_port == null) {
        return Error.NoInputPort;
    }
    defer _ = c.jack_port_unregister(client, input_port);
    const output_port = c.jack_port_register(client, "output", c.JACK_DEFAULT_AUDIO_TYPE, c.JackPortIsOutput, 0);
    if (output_port == null) {
        return Error.NoOutputPort;
    }
    defer _ = c.jack_port_unregister(client, output_port);

    // activate the client
    if (c.jack_activate(client) != 0) {
        return Error.CannotActivate;
    }
    defer _ = c.jack_deactivate(client);

    // attempt to connect to input and output ports
    const input = c.jack_get_ports(client, "", "", c.JackPortIsPhysical | c.JackPortIsOutput);

    if (c.jack_connect(client, input[0], c.jack_port_name(input_port)) != 0) {
        return Error.CannotConnectInput;
    }

    const output = c.jack_get_ports(client, "", "", c.JackPortIsPhysical | c.JackPortIsInput);
    if (output == null) {
        return Error.NoOutputPort;
    }
    std.debug.print("{any}\n", .{@TypeOf(output)});
    for (output) |o| {
        std.debug.print("{any}\n", .{o});
    }

    if (c.jack_connect(client, output[0], c.jack_port_name(output_port)) != 0) {
        return Error.CannotConnectOutput;
    }

    std.debug.print("sleeping\n", .{});
    std.time.sleep(std.time.ns_per_s);
    std.debug.print("waking up\n", .{});
}

fn processCallback(nframes: c.jack_nframes_t, arg: ?*anyopaque) callconv(.C) c_int {
    std.debug.print("+", .{});
    _ = arg;
    _ = nframes;
    return 0;
}

fn shutdownCallback(arg: ?*anyopaque) callconv(.C) void {
    _ = arg;
    std.os.exit(0);
}

// pub fn main() !void {
//     const Node = n.Sin();
//     var node = Node{};

//     for (0..480) |i| {
//         const out = node.eval(.{@as(f64, @floatFromInt(i)) * 10});
//         std.debug.print("{any}\n", .{out[0]});
//     }
// }
