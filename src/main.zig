const std = @import("std");
const n = @import("noize.zig");
const c = @cImport({
    @cInclude("portaudio.h");
});

const Error = error{
    NotInitialized,
    UnanticipatedHostError,
    InvalidChannelCount,
    InvalidSampleRate,
    InvalidDevice,
    InvalidFlag,
    SampleFormatNotSupported,
    BadIODeviceCombination,
    InsufficientMemory,
    BufferTooBig,
    BufferTooSmall,
    NullCallback,
    BadStreamPtr,
    TimedOut,
    InternalError,
    DeviceUnavailable,
    IncompatibleHostApiSpecificStreamInfo,
    StreamIsStopped,
    StreamIsNotStopped,
    InputOverflowed,
    OutputUnderflowed,
    HostApiNotFound,
    InvalidHostApi,
    CanNotReadFromACallbackStream,
    CanNotWriteToACallbackStream,
    CanNotReadFromAnOutputOnlyStream,
    CanNotWriteToAnInputOnlyStream,
    IncompatibleStreamHostApi,
    BadBufferPtr,
};

fn withErr(err: c.PaErrorCode) Error!void {
    return switch (err) {
        c.paNoError => return,
        c.paNotInitialized => Error.NotInitialized,
        c.paUnanticipatedHostError => Error.UnanticipatedHostError,
        c.paInvalidChannelCount => Error.InvalidChannelCount,
        c.paInvalidSampleRate => Error.InvalidSampleRate,
        c.paInvalidDevice => Error.InvalidDevice,
        c.paInvalidFlag => Error.InvalidFlag,
        c.paSampleFormatNotSupported => Error.SampleFormatNotSupported,
        c.paBadIODeviceCombination => Error.BadIODeviceCombination,
        c.paInsufficientMemory => Error.InsufficientMemory,
        c.paBufferTooBig => Error.BufferTooBig,
        c.paBufferTooSmall => Error.BufferTooSmall,
        c.paNullCallback => Error.NullCallback,
        c.paBadStreamPtr => Error.BadStreamPtr,
        c.paTimedOut => Error.TimedOut,
        c.paInternalError => Error.InternalError,
        c.paDeviceUnavailable => Error.DeviceUnavailable,
        c.paIncompatibleHostApiSpecificStreamInfo => Error.IncompatibleHostApiSpecificStreamInfo,
        c.paStreamIsStopped => Error.StreamIsStopped,
        c.paStreamIsNotStopped => Error.StreamIsNotStopped,
        c.paInputOverflowed => Error.InputOverflowed,
        c.paOutputUnderflowed => Error.OutputUnderflowed,
        c.paHostApiNotFound => Error.HostApiNotFound,
        c.paInvalidHostApi => Error.InvalidHostApi,
        c.paCanNotReadFromACallbackStream => Error.CanNotReadFromACallbackStream,
        c.paCanNotWriteToACallbackStream => Error.CanNotWriteToACallbackStream,
        c.paCanNotReadFromAnOutputOnlyStream => Error.CanNotReadFromAnOutputOnlyStream,
        c.paCanNotWriteToAnInputOnlyStream => Error.CanNotWriteToAnInputOnlyStream,
        c.paIncompatibleStreamHostApi => Error.IncompatibleStreamHostApi,
        c.paBadBufferPtr => Error.BadBufferPtr,
        else => @panic("unknown error code"),
    };
}

const UserData = struct {};
var data = UserData{};

fn callback(
    inputBuffer: ?*const anyopaque,
    outputBuffer: ?*anyopaque,
    framesPerBuffer: c_ulong,
    timeInfo: [*c]const c.PaStreamCallbackTimeInfo,
    statusFlags: c.PaStreamCallbackFlags,
    userData: ?*anyopaque,
) callconv(.C) c_int {
    _ = userData;
    _ = statusFlags;
    _ = timeInfo;
    _ = framesPerBuffer;
    _ = outputBuffer;
    _ = inputBuffer;
    return 0;
}

pub fn main() !void {
    const stream: [*c]?*c.PaStream = null;
    try withErr(c.Pa_Initialize());
    defer _ = c.Pa_Terminate();

    try withErr(c.Pa_OpenDefaultStream(stream, 2, 2, c.paFloat32, 48000, 256, &callback, &data));
    defer _ = c.Pa_CloseStream(stream.*);
    std.debug.print("{any}\n", .{stream});

    c.Pa_Sleep(2000);

    try withErr(c.Pa_StartStream(stream.*));
    defer _ = c.Pa_StopStream(stream);
}

// pub fn main() !void {
//     const Node = n.Sin();
//     var node = Node{};

//     for (0..480) |i| {
//         const out = node.eval(.{@as(f64, @floatFromInt(i)) * 10});
//         std.debug.print("{any}\n", .{out[0]});
//     }
// }
