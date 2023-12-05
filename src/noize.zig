const std = @import("std");
const comptimePrint = std.fmt.comptimePrint;
const builtin = std.builtin;
const expect = std.testing.expect;
const Type = std.builtin.Type;

/// kind of data that can be transmitted between blocks
pub const Kind = enum {
    float,
    int,
};

pub const Data = union(Kind) {
    float: f64,
    int: i64,

    inline fn init(k: Kind) Data {
        switch (k) {
            .float => return Data{ .float = 0 },
            .int => return Data{ .int = 0 },
        }
    }

    inline fn zero(self: *Data) void {
        switch (self.*) {
            Kind.float => self.float = 0,
            Kind.int => self.int = 0,
        }
    }

    inline fn add(self: Data, other: Data) Data {
        switch (self) {
            Kind.float => return Data{ .float = self.float + other.float },
            Kind.int => return Data{ .int = self.int + other.int },
        }
    }

    inline fn mul(self: Data, other: Data) Data {
        switch (self) {
            Kind.float => return Data{ .float = self.float * other.float },
            Kind.int => return Data{ .int = self.int * other.int },
        }
    }
};

fn dataInit(comptime S: usize, kinds: [S]Kind) [S]Data {
    var arr: [S]Data = undefined;
    for (kinds, 0..) |k, i| {
        arr[i] = Data.init(k);
    }
    return arr;
}

fn reset(data: []Data) void {
    for (data) |*d| d.zero();
}

test "reset" {
    var data = [2]Data{
        .{ .float = 23 },
        .{ .int = 42 },
    };
    var expected = [2]Data{
        .{ .float = 0 },
        .{ .int = 0 },
    };
    reset(&data);
    try std.testing.expectEqualSlices(Data, &expected, &data);
}

test "data add" {
    var a = Data{ .float = 23 };
    var b = Data{ .float = 42 };
    a = a.add(b);
    try expect(a.float == 23 + 42);
}

test "data mul" {
    var a = Data{ .float = 23 };
    var b = Data{ .float = 42 };
    a = a.mul(b);
    try expect(a.float == 23 * 42);
}

/// the main struct, that should connect to the outside
pub fn Noize(
    comptime I: usize, // number of inputs
    comptime KI: [I]Kind, // kind of inputs
    comptime O: usize, // number of outputs
    comptime KO: [O]Kind, // kind of outputs
    comptime B: type, // root evaluation block
) type {
    if (!std.mem.eql(Kind, &KI, &B.Input) or !std.mem.eql(Kind, &KO, &B.Output)) {
        @compileError("mismatch");
    }

    return struct {
        pub const Input = KI;
        pub const Output = KO;

        block: B = B{},
        input: [I]Data = dataInit(I, KI),
        output: [O]Data = dataInit(O, KO),

        const Self = @This();
        pub fn eval(self: *Self) void {
            self.block.eval(&self.input, &self.output);
        }
    };
}

/// identity function, mostly for testing purpose
pub fn Id(comptime k: Kind) type {
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

/// add two entries
pub fn Add(comptime k: Kind) type {
    return struct {
        pub const Input = [2]Kind{ k, k };
        pub const Output = [1]Kind{k};

        const Self = @This();
        fn eval(self: *Self, input: []Data, output: []Data) void {
            _ = self;
            output[0] = input[0].add(input[1]);
        }
    };
}

test "add" {
    var n = Noize(
        2,
        [_]Kind{ .int, .int },
        1,
        [_]Kind{.int},
        Add(.int),
    ){};

    n.input[0].int = 23;
    n.input[1].int = 42;
    n.eval();
    var expected = [_]Data{
        .{ .int = 23 + 42 },
    };
    try std.testing.expectEqualSlices(Data, &expected, &n.output);
}

/// connect two blocks as a sequence
pub fn Seq(comptime A: type, comptime B: type) type {
    // check for mismatch between A.Output and B.Input
    if (!std.mem.eql(Kind, &A.Output, &B.Input)) {
        @compileError("mismatch");
    }

    const buflen = A.Output.len;

    return struct {
        prev: A = A{},
        next: B = B{},
        buffer: [buflen]Data = dataInit(A.Output.len, A.Output),

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
    var n = Noize(
        1,
        [_]Kind{.float},
        1,
        [_]Kind{.float},
        Seq(Id(.float), Id(.float)),
    ){};
    n.input[0].float = 23;
    n.eval();
    try std.testing.expectEqualSlices(Data, &n.input, &n.output);
}

pub fn Par(comptime A: type, comptime B: type) type {
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
    var n = Noize(
        2,
        [_]Kind{ .int, .float },
        2,
        [_]Kind{ .int, .float },
        Par(Id(.int), Id(.float)),
    ){};

    n.input = [2]Data{
        .{ .int = 23 },
        .{ .float = 42 },
    };
    n.eval();
    try std.testing.expectEqualSlices(Data, &n.input, &n.output);
}

pub fn Merge(comptime A: type, comptime B: type) type {
    const big = A.Output.len;
    const small = B.Input.len;
    if (big % small != 0) {
        @compileError("length mismatch");
    }
    // checking if types match
    const repeat = B.Input ** @divExact(big, small);
    if (!std.mem.eql(Kind, &repeat, &A.Output)) {
        @compileError("type mismatch");
    }

    return struct {
        a: A = A{},
        b: B = B{},
        bigbuf: [big]Data = dataInit(big, A.Output),
        smallbuf: [small]Data = dataInit(small, B.Input),

        pub const Input = A.Input;
        pub const Output = B.Output;

        const Self = @This();
        fn eval(self: *Self, input: []Data, output: []Data) void {
            // eval first block
            self.a.eval(input[0..Input.len], &self.bigbuf);
            // compute merge
            reset(&self.smallbuf);
            for (self.bigbuf, 0..) |v, i| {
                self.smallbuf[i % small] = self.smallbuf[i % small].add(v);
            }
            // eval second block
            self.b.eval(&self.smallbuf, output[0..Output.len]);
        }
    };
}

test "merge" {
    var n = Noize(
        4,
        [_]Kind{.float} ** 4,
        2,
        [_]Kind{.float} ** 2,
        Merge(
            Par(Par(Id(.float), Id(.float)), Par(Id(.float), Id(.float))),
            Par(Id(.float), Id(.float)),
        ),
    ){};
    n.input[0].float = 1;
    n.input[1].float = 2;
    n.input[2].float = 4;
    n.input[3].float = 8;
    n.eval();
    // expected: 5, 10
    const expected = [2]Data{
        .{ .float = 5 },
        .{ .float = 10 },
    };
    try std.testing.expectEqualSlices(Data, &expected, &n.output);
}

pub fn Split(comptime A: type, comptime B: type) type {
    const small = A.Output.len;
    const big = B.Input.len;
    if (big % small != 0) {
        @compileError("length mismatch");
    }
    // checking if types match
    const repeat = A.Output ** @divExact(big, small);
    if (!std.mem.eql(Kind, &repeat, &B.Input)) {
        @compileError("type mismatch");
    }

    return struct {
        a: A = A{},
        b: B = B{},
        bigbuf: [big]Data = dataInit(big, B.Input),
        smallbuf: [small]Data = dataInit(small, A.Output),

        pub const Input = A.Input;
        pub const Output = B.Output;

        const Self = @This();
        fn eval(self: *Self, input: []Data, output: []Data) void {
            // eval first block
            self.a.eval(input[0..Input.len], &self.smallbuf);
            // compute split
            self.bigbuf = self.smallbuf ** @divExact(big, small);
            // eval second block
            self.b.eval(&self.bigbuf, output[0..Output.len]);
        }
    };
}

test "split" {
    var n = Noize(
        2,
        [_]Kind{.float} ** 2,
        4,
        [_]Kind{.float} ** 4,
        Split(
            Par(Id(.float), Id(.float)),
            Par(Par(Id(.float), Id(.float)), Par(Id(.float), Id(.float))),
        ),
    ){};
    n.input[0].float = 1;
    n.input[1].float = 2;
    n.eval();
    const expected = [4]Data{
        .{ .float = 1 },
        .{ .float = 2 },
        .{ .float = 1 },
        .{ .float = 2 },
    };
    try std.testing.expectEqualSlices(Data, &expected, &n.output);
}

pub fn Rec(comptime A: type, comptime B: type) type {
    if (B.Input.len != A.Output.len) {
        @compileError("length mismatch : A --> B");
    }

    if (!std.mem.eql(Kind, &B.Input, &A.Output)) {
        @compileError("type mismatch : A --> B");
    }

    if (A.Input.len < B.Output.len) {
        @compileError("length mismatch : B --> A");
    }

    if (!std.mem.eql(Kind, A.Input[0..B.Output.len], &B.Output)) {
        @compileError("type mismatch : B --> A");
    }

    const split = B.Output.len;
    comptime var input_kind: [A.Input.len - split]Kind = undefined;
    @memcpy(&input_kind, A.Input[split..]);

    return struct {
        a: A = A{},
        b: B = B{},
        buf_a: [A.Input.len]Data = dataInit(A.Input.len, A.Input),
        buf_b: [B.Input.len]Data = dataInit(B.Input.len, B.Input),

        pub const Input = input_kind;
        pub const Output = A.Output;

        const Self = @This();
        fn eval(self: *Self, input: []Data, output: []Data) void {
            // eval B from previous iteration
            // store the result in the first part of A's input buffer
            self.b.eval(&self.buf_b, self.buf_a[0..split]);
            // complete A's input buffer with external source
            @memcpy(self.buf_a[split..], input);
            // eval A
            self.a.eval(&self.buf_a, output[0..A.Output.len]);
            // copy output for next iteration
            @memcpy(&self.buf_b, output[0..A.Output.len]);
        }
    };
}

test "rec" {
    var n = Noize(
        1,
        [_]Kind{.int},
        1,
        [_]Kind{.int},
        Rec(
            Add(.int),
            Id(.int),
        ),
    ){};
    n.input[0].int = 1;
    n.eval();
    try expect(n.output[0].int == 1);
    n.eval();
    try expect(n.output[0].int == 2);
    n.input[0].int = 4;
    n.eval();
    try expect(n.output[0].int == 6);
}
