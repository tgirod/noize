const std = @import("std");
const comptimePrint = std.fmt.comptimePrint;
const builtin = std.builtin;

const Kind = enum {
    float,
    int,
};

const Data = union(Kind) {
    float: f64,
    int: i64,
};

fn Id(comptime k: Kind) type {
    return struct {
        pub const Input = [1]Kind{k};
        pub const Output = [1]Kind{k};

        const Self = @This();
        fn eval(self: *Self, input: []Data, output: []Data) void {
            _ = self;
            output[0] = input[0];
        }
    };
}

pub fn main() void {
    var i = Id(Kind.int){};
    var in = [_]Data{.{ .int = 23 }};
    var out = [_]Data{.{ .int = 0 }};
    i.eval(&in, &out);
    std.debug.print("{any}\n", .{out});
}
