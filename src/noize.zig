const std = @import("std");
const comptimePrint = std.fmt.comptimePrint;
const builtin = std.builtin;
const expect = std.testing.expect;
const Type = std.builtin.Type;

/// any data exchanged between blocks is of type Data
pub const Data = union(enum) {
    const Self = @This();
    pub const Tag = std.meta.Tag(Self);

    float: f64,
    int: i64,
    uint: u64,

    /// creates Data of a given tag with 0 value
    inline fn init(t: Data.Tag) Data {
        switch (t) {
            .float => return Data{ .float = 0 },
            .int => return Data{ .int = 0 },
            .uint => return Data{ .uint = 0 },
        }
    }

    /// creates an array of Data of a given size, with given tags
    fn arrayInit(comptime S: usize, tags: [S]Data.Tag) [S]Data {
        var arr: [S]Data = undefined;
        for (tags, 0..) |t, i| {
            arr[i] = Data.init(t);
        }
        return arr;
    }

    /// resets to zero value
    inline fn zero(self: *Data) void {
        switch (self.*) {
            Data.Tag.float => self.float = 0,
            Data.Tag.int => self.int = 0,
            Data.Tag.uint => self.uint = 0,
        }
    }

    /// resets an array to zero
    inline fn arrayZero(data: []Data) void {
        for (data) |*d| d.zero();
    }

    /// adds two Data of the same type
    inline fn add(self: Data, other: Data) Data {
        switch (self) {
            Data.Tag.float => return Data{ .float = self.float + other.float },
            Data.Tag.int => return Data{ .int = self.int + other.int },
            Data.Tag.uint => return Data{ .uint = self.uint + other.uint },
        }
    }

    /// multiplies two Data of the same type
    inline fn mul(self: Data, other: Data) Data {
        switch (self) {
            Data.Tag.float => return Data{ .float = self.float * other.float },
            Data.Tag.int => return Data{ .int = self.int * other.int },
            Data.Tag.uint => return Data{ .uint = self.uint * other.uint },
        }
    }
};

test "Data.arrayZero" {
    var data = [2]Data{
        .{ .float = 23 },
        .{ .int = 42 },
    };
    var expected = [2]Data{
        .{ .float = 0 },
        .{ .int = 0 },
    };
    Data.arrayZero(&data);
    try std.testing.expectEqualSlices(Data, &expected, &data);
}

test "data.arrayInit" {
    var d = Data.arrayInit(2, [_]Data.Tag{ .float, .int });
    try std.testing.expectEqualSlices(
        Data,
        &[2]Data{ .{ .float = 0 }, .{ .int = 0 } },
        &d,
    );
}

test "Data.add" {
    var a = Data{ .float = 23 };
    var b = Data{ .float = 42 };
    a = a.add(b);
    try expect(a.float == 23 + 42);
}

test "Data.mul" {
    var a = Data{ .float = 23 };
    var b = Data{ .float = 42 };
    a = a.mul(b);
    try expect(a.float == 23 * 42);
}

/// the main struct, that should connect to the outside
pub fn Noize(
    comptime I: usize, // number of inputs
    comptime TI: [I]Data.Tag, // tag of inputs
    comptime O: usize, // number of outputs
    comptime TO: [O]Data.Tag, // tag of outputs
    comptime B: type, // root evaluation block
) type {
    if (!std.mem.eql(Data.Tag, &TI, &B.Input) or !std.mem.eql(Data.Tag, &TO, &B.Output)) {
        @compileError("mismatch");
    }

    return struct {
        pub const Input = TI;
        pub const Output = TO;

        block: B = B{},
        input: [I]Data = Data.arrayInit(I, TI),
        output: [O]Data = Data.arrayInit(O, TO),

        const Self = @This();
        pub fn eval(self: *Self) void {
            self.block.eval(&self.input, &self.output);
        }
    };
}

/// identity function, mostly for testing purpose
pub fn Id(comptime t: Data.Tag) type {
    return struct {
        pub const Input = [1]Data.Tag{t};
        pub const Output = [1]Data.Tag{t};

        const Self = @This();
        fn eval(self: *Self, input: []Data, output: []Data) void {
            _ = self;
            output[0] = input[0];
        }
    };
}

/// add two entries
pub fn Add(comptime t: Data.Tag) type {
    return struct {
        pub const Input = [2]Data.Tag{ t, t };
        pub const Output = [1]Data.Tag{t};

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
        [_]Data.Tag{ .int, .int },
        1,
        [_]Data.Tag{.int},
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
    if (!std.mem.eql(Data.Tag, &A.Output, &B.Input)) {
        @compileError("mismatch");
    }

    const buflen = A.Output.len;

    return struct {
        prev: A = A{},
        next: B = B{},
        buffer: [buflen]Data = Data.arrayInit(A.Output.len, A.Output),

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
        [_]Data.Tag{.float},
        1,
        [_]Data.Tag{.float},
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
        [_]Data.Tag{ .int, .float },
        2,
        [_]Data.Tag{ .int, .float },
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
    if (!std.mem.eql(Data.Tag, &repeat, &A.Output)) {
        @compileError("type mismatch");
    }

    return struct {
        a: A = A{},
        b: B = B{},
        bigbuf: [big]Data = Data.arrayInit(big, A.Output),
        smallbuf: [small]Data = Data.arrayInit(small, B.Input),

        pub const Input = A.Input;
        pub const Output = B.Output;

        const Self = @This();
        fn eval(self: *Self, input: []Data, output: []Data) void {
            // eval first block
            self.a.eval(input[0..Input.len], &self.bigbuf);
            // compute merge
            Data.arrayZero(&self.smallbuf);
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
        [_]Data.Tag{.float} ** 4,
        2,
        [_]Data.Tag{.float} ** 2,
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
    if (!std.mem.eql(Data.Tag, &repeat, &B.Input)) {
        @compileError("type mismatch");
    }

    return struct {
        a: A = A{},
        b: B = B{},
        bigbuf: [big]Data = Data.arrayInit(big, B.Input),
        smallbuf: [small]Data = Data.arrayInit(small, A.Output),

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
        [_]Data.Tag{.float} ** 2,
        4,
        [_]Data.Tag{.float} ** 4,
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

    if (!std.mem.eql(Data.Tag, &B.Input, &A.Output)) {
        @compileError("type mismatch : A --> B");
    }

    if (A.Input.len < B.Output.len) {
        @compileError("length mismatch : B --> A");
    }

    if (!std.mem.eql(Data.Tag, A.Input[0..B.Output.len], &B.Output)) {
        @compileError("type mismatch : B --> A");
    }

    const split = B.Output.len;
    comptime var input_tag: [A.Input.len - split]Data.Tag = undefined;
    @memcpy(&input_tag, A.Input[split..]);

    return struct {
        a: A = A{},
        b: B = B{},
        buf_a: [A.Input.len]Data = Data.arrayInit(A.Input.len, A.Input),
        buf_b: [B.Input.len]Data = Data.arrayInit(B.Input.len, B.Input),

        pub const Input = input_tag;
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
        [_]Data.Tag{.int},
        1,
        [_]Data.Tag{.int},
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

/// takes a size S and a block type B, and duplicate B S times in parallel
pub fn Dup(comptime S: usize, comptime B: type) type {
    return struct {
        blocks: [S]B = [_]B{B{}} ** S,

        pub const Input = B.Input ** S;
        pub const Output = B.Output ** S;

        const Self = @This();

        fn eval(self: *Self, input: []Data, output: []Data) void {
            const in_step = B.Input.len;
            const out_step = B.Output.len;
            for (0..S) |i| {
                self.blocks[i].eval(
                    input[i * in_step .. (i + 1) * in_step],
                    output[i * out_step .. (i + 1) * out_step],
                );
            }
        }
    };
}

test "dup" {
    const s = 4;
    var n = Noize(
        s,
        [_]Data.Tag{.float} ** s,
        s,
        [_]Data.Tag{.float} ** s,
        Dup(s, Id(.float)),
    ){};
    try expect(@TypeOf(n).Input.len == s);
    try expect(@TypeOf(n).Output.len == s);
    n.input = [_]Data{.{ .float = 1 }} ** s;
    n.eval();
    try std.testing.expectEqualSlices(Data, &n.input, &n.output);
}

pub fn Delay(comptime t: Data.Tag, comptime S: usize) type {
    if (S == 0) {
        @compileError("delay length == 0");
    }

    return struct {
        pub const Input = [1]Data.Tag{t};
        pub const Output = [1]Data.Tag{t};

        buffer: [S]Data = [1]Data{Data.init(t)} ** S,
        pos: usize = 0,

        const Self = @This();
        fn eval(self: *Self, input: []Data, output: []Data) void {
            output[0] = self.buffer[self.pos];
            self.buffer[self.pos] = input[0];
            self.pos = (self.pos + 1) % S;
        }
    };
}

test "delay" {
    var n = Noize(
        1,
        [_]Data.Tag{.int},
        1,
        [_]Data.Tag{.int},
        Delay(.int, 1),
    ){};
    n.input[0].int = 1;
    n.eval();
    try expect(n.output[0].int == 0);
    n.eval();
    try expect(n.output[0].int == 1);
}
