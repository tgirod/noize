const std = @import("std");

var allo: std.mem.Allocator = undefined;
var srate: u64 = undefined;

const Error = error{
    LengthMismatch,
};

pub fn init(allocator: std.mem.Allocator, samplerate: u64) void {
    allo = allocator;
    srate = samplerate;
}

pub fn seq(prev: anyerror!Block, next: anyerror!Block) !Block {
    return Block{
        ._seq = try Seq.init(try prev, try next),
    };
}

const Seq = struct {
    prev: *const Block,
    next: *const Block,
    buffer: []f32,

    fn init(prev: *const Block, next: *const Block) !Seq {
        // allouer le buffer intermédiaire
        const buffer = try allo.alloc(f32, prev.out());
        errdefer allo.free(buffer);

        // vérifier que les dimensions correspondent
        if (prev.out() != next.in()) {
            return Error.LengthMismatch;
        }

        return Seq{
            .prev = prev,
            .next = next,
            .buffer = buffer,
        };
    }

    fn deinit(self: Seq) void {
        allo.free(self.buffer);
    }

    fn eval(self: *Seq, now: u64, input: []f32, output: []f32) void {
        self.prev.eval(now, input, self.buffer);
        self.next.eval(now, self.buffer, output);
    }

    fn in(self: Seq) usize {
        return self.prev.in();
    }

    fn out(self: Seq) usize {
        return self.next.out();
    }
};

pub fn par(first: anyerror!Block, second: anyerror!Block) !Block {
    return Block{
        ._par = try Par.init(try first, try second),
    };
}

const Par = struct {
    first: *const Block,
    second: *const Block,
    inlen: usize,
    outlen: usize,

    fn init(first: Block, second: Block) !Par {
        return Par{
            .first = &first,
            .second = &second,
            .inlen = first.in(),
            .outlen = first.out(),
        };
    }

    fn deinit(self: Par) void {
        _ = self;
    }

    fn eval(self: *Par, now: u64, input: []f32, output: []f32) void {
        self.first.eval(now, input[0..self.inlen], output[0..self.inlen]);
        self.second.eval(now, input[self.inlen..], output[self.inlen..]);
    }

    fn in(self: Par) usize {
        return self.first.in() + self.second.in();
    }

    fn out(self: Par) usize {
        return self.first.out() + self.second.out();
    }
};

pub fn merge(prev: anyerror!Block, next: anyerror!Block) !Block {
    return Block{
        ._merge = Merge.init(try prev, try next),
    };
}

const Merge = struct {
    prev: *const Block,
    next: *const Block,
    prevbuf: []f32,
    nextbuf: []f32,

    fn init(prev: Block, next: Block) !Merge {
        const prevbuf = try allo.alloc(f32, prev.out());
        errdefer allo.free(prevbuf);
        const nextbuf = try allo.alloc(f32, next.in());
        errdefer allo.free(nextbuf);

        if (prevbuf.len % nextbuf.len != 0) {
            return Error.LengthMismatch;
        }

        return Merge{
            .prev = &prev,
            .next = &next,
            .prevbuf = prevbuf,
            .nextbuf = nextbuf,
        };
    }

    fn deinit(self: Merge) void {
        allo.free(self.prevbuf);
        allo.free(self.nextbuf);
        self.prev.deinit();
        self.next.deinit();
    }

    fn eval(self: *Merge, now: u64, input: []f32, output: []f32) void {
        // eval prev
        self.prev.eval(now, input, self.prevbuf);
        // do the merging
        for (self.prevbuf, 0..) |p, i| {
            if (i < self.nextbuf.len) {
                self.nextbuf[i % self.nextbuf.len] = p;
            } else {
                self.nextbuf[i % self.nextbuf.len] += p;
            }
        }
        // eval next
        self.next.eval(now, self.nextbuf, output);
    }

    fn in(self: Merge) usize {
        return self.prev.in();
    }

    fn out(self: Merge) usize {
        return self.next.out();
    }
};

pub fn split(prev: anyerror!Block, sibling: anyerror!Block) !Block {
    return Block{
        ._split = Split.init(try prev, try sibling),
    };
}

const Split = struct {
    prev: *const Block,
    next: *const Block,
    buffer: []f32,

    fn init(prev: Block, next: Block) !Split {
        const buffer = try allo.alloc(f32, next.in());
        errdefer allo.free(buffer);

        if (next.in() % prev.out() != 0) {
            return Error.LengthMismatch;
        }

        return Split{
            .prev = &prev,
            .next = &next,
            .buffer = buffer,
        };
    }

    fn deinit(self: Split) void {
        allo.free(self.buffer);
        self.prev.deinit();
        self.next.deinit();
    }

    fn eval(self: *Split, now: u64, input: []f32, output: []f32) void {
        const prevlen = self.prev.out();
        const nextlen = self.next.in();

        // eval prev
        self.prev.eval(now, input, self.buffer[0..prevlen]);
        // do the splitting
        for (prevlen..nextlen) |i| {
            self.buffer[i] = self.buffer[i % prevlen];
        }
        // eval next
        self.next.eval(now, self.buffer, output);
    }

    fn in(self: Split) usize {
        return self.prev.in();
    }

    fn out(self: Split) usize {
        return self.next.out();
    }
};

pub fn rec(forward: anyerror!Block, loop: anyerror!Block) !Block {
    return Block{
        ._rec = Rec.init(try forward, try loop),
    };
}

const Rec = struct {
    // forward.out == loop.in
    // forward.in > loop.out
    forward: *const Block,
    loop: *const Block,
    forwardbuf: []f32, // forward input buffer
    loopbuf: []f32, // loop input buffer

    fn init(forward: Block, loop: Block) !Rec {
        if (forward.out() != loop.in()) {
            return Error.LengthMismatch;
        }

        if (loop.out() > forward.in()) {
            return Error.LengthMismatch;
        }

        const forwardbuf = try allo.alloc(f32, forward.in());
        errdefer allo.free(forwardbuf);
        @memset(forwardbuf, 0);

        const loopbuf = try allo.alloc(f32, loop.in());
        errdefer allo.free(loopbuf);
        @memset(forwardbuf, 0);

        return Rec{
            .forward = &forward,
            .loop = &loop,
            .forwardbuf = forwardbuf,
            .loopbuf = loopbuf,
        };
    }

    fn deinit(self: Rec) void {
        allo.free(self.forwardbuf);
        allo.free(self.loopbuf);
        self.forward.deinit();
        self.loop.deinit();
    }

    fn eval(self: *Rec, now: u64, input: []f32, output: []f32) void {
        // eval loopback based on previous iteration result
        self.loop.eval(now, self.loopbuf, self.forwardbuf[0..self.loopbuf.len]);
        // append current input
        @memcpy(self.forwardbuf[self.loopbuf.len..], input);
        // eval forward
        self.forward.eval(now, self.forwardbuf, output);
        // copy current eval for next iteration
        @memcpy(self.loopbuf, output);
    }

    fn in(self: Rec) usize {
        return self.forward.in() - self.loop.out();
    }

    fn out(self: Rec) usize {
        return self.forward.out();
    }
};

pub fn delay(length: usize) !Block {
    return Block{
        ._delay = try Delay.init(length),
    };
}

const Delay = struct {
    buffer: []f32,
    pos: u64,

    fn init(length: usize) !Delay {
        const buffer = try allo.alloc(f32, length);
        return Delay{
            .buffer = buffer,
            .pos = 0,
        };
    }

    fn deinit(self: Delay) void {
        allo.free(self.buffer);
    }

    fn eval(self: *Delay, now: u64, input: []f32, output: []f32) void {
        _ = now;
        output[0] = self.buffer[self.pos];
        self.buffer[self.pos] = input[0];
        self.pos = (self.pos + 1) % self.buffer.len;
    }

    fn in(self: Delay) usize {
        _ = self;
        return 1;
    }

    fn out(self: Delay) usize {
        _ = self;
        return 1;
    }
};

pub fn add() !Block {
    return Block{
        ._add = Add.init(),
    };
}

const Add = struct {
    fn init() Add {
        return Add{};
    }

    fn deinit(self: Add) void {
        _ = self;
    }

    fn eval(self: *Add, now: u64, input: []f32, output: []f32) void {
        _ = now;
        _ = self;
        output[0] = input[0] + input[1];
    }

    fn in(self: Add) usize {
        _ = self;
        return 2;
    }

    fn out(self: Add) usize {
        _ = self;
        return 1;
    }
};

pub fn mul() !Block {
    return Block{
        ._mul = Mul.init(),
    };
}

const Mul = struct {
    fn init() Mul {
        return Mul{};
    }

    fn deinit(self: Mul) void {
        _ = self;
    }

    fn eval(self: *Mul, now: u64, input: []f32, output: []f32) void {
        _ = now;
        _ = self;
        output[0] = input[0] * input[1];
    }

    fn in(self: Mul) usize {
        _ = self;
        return 2;
    }

    fn out(self: Mul) usize {
        _ = self;
        return 1;
    }
};

pub fn neg() !Block {
    return Block{
        ._neg = Neg.init(),
    };
}

const Neg = struct {
    fn init() Neg {
        return Neg{};
    }

    fn deinit(self: Neg) void {
        _ = self;
    }

    fn eval(self: *Neg, now: u64, input: []f32, output: []f32) void {
        _ = now;
        _ = self;
        output[0] = -input[0];
    }

    fn in(self: Neg) usize {
        _ = self;
        return 1;
    }

    fn out(self: Neg) usize {
        _ = self;
        return 1;
    }
};

pub fn sin() !Block {
    return Block{
        ._sin = Sin.init(),
    };
}

const Sin = struct {
    fn init() Sin {
        return Sin{};
    }

    fn deinit(self: Sin) void {
        _ = self;
    }

    fn eval(self: *Sin, now: u64, input: []f32, output: []f32) void {
        _ = self;
        const freq = input[0];
        const phase = @as(f32, @floatFromInt(now)) / @as(f32, @floatFromInt(srate)) * freq * std.math.tau;
        output[0] = @sin(phase);
    }

    fn in(self: Sin) usize {
        _ = self;
        return 1;
    }

    fn out(self: Sin) usize {
        _ = self;
        return 1;
    }
};

const Block = union(enum) {
    pub fn deinit(self: Block) void {
        switch (self) {
            inline else => |impl| impl.deinit(),
        }
    }

    pub fn eval(self: Block, now: u64, input: []f32, output: []f32) void {
        // FIXME pass a pointer to self
        switch (self) {
            inline else => |impl| impl.eval(now, input, output),
        }
    }

    fn in(self: Block) usize {
        switch (self) {
            inline else => |impl| return impl.in(),
        }
    }

    fn out(self: Block) usize {
        switch (self) {
            inline else => |impl| return impl.out(),
        }
    }

    // connectors
    _seq: Seq,
    _par: Par,
    _merge: Merge,
    _split: Split,
    _rec: Rec,

    // base blocks
    _delay: Delay,
    _add: Add,
    _mul: Mul,
    _neg: Neg,
    _sin: Sin,
};
