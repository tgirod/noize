const std = @import("std");
const comptimePrint = std.fmt.comptimePrint;
const builtin = std.builtin;
const expect = std.testing.expect;

/// kind of data that can be transmitted between blocks
const Kind = enum {
    float,
    int,
    uint,
};

const Data = union(Kind) {
    float: f64,
    int: i64,
    uint: u64,
};

/// identity function
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

/// connect two blocks as a sequence
fn Seq(comptime A: type, comptime B: type) type {
    // check for type mismatch
    for (A.Output, B.Input) |a, b| {
        if (a != b) {
            @compileError("type mismatch");
        }
    }

    const buflen = A.Output.len;

    return struct {
        prev: A = A{},
        next: B = B{},
        buffer: [buflen]Data = undefined,

        pub const Input = A.Input;
        pub const Output = B.Output;

        const Self = @This();

        fn eval(self: *Self, input: []Data, output: []Data) void {
            self.prev.eval(input, &self.buffer);
            self.next.eval(&self.buffer, output);
        }
    };
}

test "seq" {
    const Noize = Seq(Id(.float), Id(.float));
    var in = [Noize.Input.len]Data{
        .{ .float = 23 },
    };
    var out = [Noize.Output.len]Data{
        .{ .float = 0 },
    };

    var n = Noize{};
    n.eval(&in, &out);
    try std.testing.expectEqualSlices(Data, &in, &out);
}

fn Par(comptime A: type, comptime B: type) type {
    return struct {
        a: A = A{},
        b: B = B{},

        pub const Input = A.Input ++ B.Input;
        pub const Output = A.Output ++ B.Output;

        const Self = @This();
        const pivot_input = A.Input.len;
        const pivot_output = A.Output.len;

        fn eval(self: *Self, input: []Data, output: []Data) void {
            self.a.eval(input[0..pivot_input], output[0..pivot_output]);
            self.b.eval(input[pivot_input..], output[pivot_output..]);
        }
    };
}

test "par" {
    const Noize = Par(Id(.int), Id(.float));
    var in = [Noize.Input.len]Data{
        .{ .int = 23 },
        .{ .float = 42 },
    };
    var out = [Noize.Output.len]Data{
        .{ .int = 0 },
        .{ .float = 0 },
    };

    var n = Noize{};
    n.eval(&in, &out);
    try std.testing.expectEqualSlices(Data, &in, &out);
}

pub fn main() void {
    const Tree = Seq(Id(Kind.int), Id(Kind.int));
    var t = Tree{};
    std.debug.print("{any}\n", .{t});
    var in: [1]Data = undefined;
    in[0] = .{ .int = 23 };
    var out: [1]Data = undefined;
    out[0] = .{ .int = 0 };

    t.eval(&in, &out);
    std.debug.print("{any}\n", .{out});
}
