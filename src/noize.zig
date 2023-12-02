const std = @import("std");
const expect = std.testing.expect;

var allo: std.mem.Allocator = undefined;
var srate: u64 = undefined;
pub var in: []f32 = undefined;
pub var out: []f32 = undefined;

const Error = error{
    LengthMismatch,
};

pub fn init(allocator: std.mem.Allocator, samplerate: u64, inputSize: usize, outputSize: usize) !void {
    allo = allocator;
    srate = samplerate;
    in = try allo.alloc(f32, inputSize);
    errdefer allo.free(in);
    out = try allo.alloc(f32, outputSize);
    errdefer allo.free(out);
}

pub fn deinit() void {
    allo.free(in);
    allo.free(out);
}

test "init / deinit" {
    try init(std.testing.allocator, 48000, 1, 2);
    defer deinit();
    try expect(in.len == 1);
    try expect(out.len == 2);
}

const Block = union(enum) {
    // connectors
    seq: *Seq,
    par: *Par,
    merge: *Merge,
    split: *Split,
    rec: *Rec,

    // base blocks
    delay: *Delay,
    add: *Add,
    mul: *Mul,
    neg: *Neg,
    sin: *Sin,
    val: *Val,
    id: *Id,
    wave: *Wave,

    // eval one timestep
    pub fn eval(self: Block, now: u64, input: []f32, output: []f32) void {
        switch (self) {
            inline else => |impl| impl.eval(now, input, output),
        }
    }

    // input size
    fn in(self: Block) usize {
        switch (self) {
            inline else => |impl| return impl.in(),
        }
    }

    // output size
    fn out(self: Block) usize {
        switch (self) {
            inline else => |impl| return impl.out(),
        }
    }

    // free allocated memory
    pub fn deinit(self: Block) void {
        switch (self) {
            inline else => |impl| impl.deinit(),
        }
    }
};

pub fn seq(prev: anyerror!Block, next: anyerror!Block) !Block {
    return Block{
        .seq = try Seq.init(try prev, try next),
    };
}

const Seq = struct {
    prev: Block,
    next: Block,
    buffer: []f32,

    fn init(prev: Block, next: Block) !*Seq {
        // vérifier que les dimensions correspondent
        if (prev.out() != next.in()) {
            return Error.LengthMismatch;
        }

        // créer le block
        var s = try allo.create(Seq);
        errdefer allo.destroy(s);

        // allouer le buffer intermédiaire
        const buffer = try allo.alloc(f32, prev.out());
        errdefer allo.free(buffer);

        s.prev = prev;
        s.next = next;
        s.buffer = buffer;
        return s;
    }

    fn deinit(self: *Seq) void {
        allo.free(self.buffer);
    }

    fn eval(self: *Seq, now: u64, input: []f32, output: []f32) void {
        self.prev.eval(now, input, self.buffer);
        self.next.eval(now, self.buffer, output);
    }

    fn in(self: *Seq) usize {
        return self.prev.in();
    }

    fn out(self: *Seq) usize {
        return self.next.out();
    }
};

test "sequence of blocks" {
    try init(std.testing.allocator, 48000, 0, 1);
    defer deinit();
    var root = try seq(val(23), id());
    defer root.deinit();
    root.eval(0, in, out);
    try expect(out[0] == 23);
}

pub fn par(first: anyerror!Block, second: anyerror!Block) !Block {
    return Block{
        .par = try Par.init(try first, try second),
    };
}

const Par = struct {
    first: Block,
    second: Block,
    inlen: usize,
    outlen: usize,

    fn init(first: Block, second: Block) !*Par {
        var p = try allo.create(Par);
        errdefer allo.destroy(p);

        p.first = first;
        p.second = second;
        p.inlen = first.in();
        p.outlen = first.out();
        return p;
    }

    fn eval(self: *Par, now: u64, input: []f32, output: []f32) void {
        self.first.eval(now, input[0..self.inlen], output[0..self.inlen]);
        self.second.eval(now, input[self.inlen..], output[self.inlen..]);
    }

    fn in(self: *Par) usize {
        return self.first.in() + self.second.in();
    }

    fn out(self: *Par) usize {
        return self.first.out() + self.second.out();
    }

    fn deinit(self: *Par) void {
        self.first.deinit();
        self.second.deinit();
    }
};

pub fn merge(prev: anyerror!Block, next: anyerror!Block) !Block {
    return Block{
        .merge = Merge.init(try prev, try next),
    };
}

const Merge = struct {
    prev: Block,
    next: Block,
    prevbuf: []f32,
    nextbuf: []f32,

    fn init(prev: Block, next: Block) !*Merge {
        if (prev.out() % next.in() != 0) {
            return Error.LengthMismatch;
        }

        var m = try allo.create(Merge);
        errdefer allo.destroy(m);

        const prevbuf = try allo.alloc(f32, prev.out());
        errdefer allo.free(prevbuf);

        const nextbuf = try allo.alloc(f32, next.in());
        errdefer allo.free(nextbuf);

        m.prev = prev;
        m.next = next;
        m.prevbuf = prevbuf;
        m.nextbuf = nextbuf;
        return m;
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

    fn in(self: *Merge) usize {
        return self.prev.in();
    }

    fn out(self: *Merge) usize {
        return self.next.out();
    }

    fn deinit(self: *Merge) void {
        self.prev.deinit();
        self.next.deinit();
        allo.free(self.prevbuf);
        allo.free(self.nextbuf);
        allo.destroy(self);
    }
};

pub fn split(prev: anyerror!Block, sibling: anyerror!Block) !Block {
    return Block{
        .split = Split.init(try prev, try sibling),
    };
}

const Split = struct {
    prev: Block,
    next: Block,
    buffer: []f32,

    fn init(prev: Block, next: Block) !Split {
        if (next.in() % prev.out() != 0) {
            return Error.LengthMismatch;
        }

        var s = try allo.create(Split);
        errdefer allo.destroy(s);

        const buffer = try allo.alloc(f32, next.in());
        errdefer allo.free(buffer);

        s.prev = prev;
        s.next = next;
        s.buffer = buffer;
        return s;
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

    fn in(self: *Split) usize {
        return self.prev.in();
    }

    fn out(self: *Split) usize {
        return self.next.out();
    }

    fn deinit(self: *Split) void {
        self.prev.deinit();
        self.next.deinit();
        allo.destroy(self);
    }
};

pub fn rec(forward: anyerror!Block, loop: anyerror!Block) !Block {
    return Block{
        .rec = Rec.init(try forward, try loop),
    };
}

const Rec = struct {
    forward: Block,
    loop: Block,
    forwardbuf: []f32, // forward input buffer
    loopbuf: []f32, // loop input buffer

    fn init(forward: Block, loop: Block) !*Rec {
        if (forward.out() != loop.in()) {
            return Error.LengthMismatch;
        }

        if (loop.out() > forward.in()) {
            return Error.LengthMismatch;
        }

        var r = try allo.create(Rec);
        errdefer allo.destroy(r);

        r.forward = forward;
        r.loop = loop;

        r.forwardbuf = try allo.alloc(f32, forward.in());
        errdefer allo.free(r.forwardbuf);
        @memset(r.forwardbuf, 0);

        r.loopbuf = try allo.alloc(f32, loop.in());
        errdefer allo.free(r.loopbuf);
        @memset(r.loopbuf, 0);

        return r;
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

    fn in(self: *Rec) usize {
        return self.forward.in() - self.loop.out();
    }

    fn out(self: *Rec) usize {
        return self.forward.out();
    }

    fn deinit(self: *Rec) void {
        self.forward.deinit();
        self.loop.deinit();
        allo.free(self.forwardbuf);
        allo.free(self.loopbuf);
    }
};

pub fn delay(length: usize) !Block {
    return Block{
        .delay = try Delay.init(length),
    };
}

const Delay = struct {
    buffer: []f32,
    pos: u64,

    fn init(length: usize) !*Delay {
        var d = try allo.create(Delay);
        errdefer allo.destroy(d);

        d.buffer = try allo.alloc(f32, length);
        errdefer allo.free(d.buffer);

        d.pos = 0;
        return d;
    }

    fn eval(self: *Delay, now: u64, input: []f32, output: []f32) void {
        _ = now;
        output[0] = self.buffer[self.pos];
        self.buffer[self.pos] = input[0];
        self.pos = (self.pos + 1) % self.buffer.len;
    }

    fn in(self: *Delay) usize {
        _ = self;
        return 1;
    }

    fn out(self: *Delay) usize {
        _ = self;
        return 1;
    }

    fn deinit(self: *Delay) void {
        allo.free(self.buffer);
    }
};

pub fn add() !Block {
    return Block{
        .add = try Add.init(),
    };
}

const Add = struct {
    fn init() !*Add {
        return try allo.create(Add);
    }

    fn eval(self: *Add, now: u64, input: []f32, output: []f32) void {
        _ = now;
        _ = self;
        output[0] = input[0] + input[1];
    }

    fn in(self: *Add) usize {
        _ = self;
        return 2;
    }

    fn out(self: *Add) usize {
        _ = self;
        return 1;
    }

    fn deinit(self: *Add) void {
        allo.destroy(self);
    }
};

pub fn mul() !Block {
    return Block{
        .mul = try Mul.init(),
    };
}

const Mul = struct {
    fn init() !*Mul {
        return try allo.create(Mul);
    }

    fn eval(self: *Mul, now: u64, input: []f32, output: []f32) void {
        _ = now;
        _ = self;
        output[0] = input[0] + input[1];
    }

    fn in(self: *Mul) usize {
        _ = self;
        return 2;
    }

    fn out(self: *Mul) usize {
        _ = self;
        return 1;
    }

    fn deinit(self: *Mul) void {
        allo.destroy(self);
    }
};

pub fn neg() !Block {
    return Block{
        .neg = try Neg.init(),
    };
}

const Neg = struct {
    fn init() !*Neg {
        return try allo.create(Neg);
    }

    fn eval(self: *Neg, now: u64, input: []f32, output: []f32) void {
        _ = now;
        _ = self;
        output[0] = -input[0];
    }

    fn in(self: *Neg) usize {
        _ = self;
        return 1;
    }

    fn out(self: *Neg) usize {
        _ = self;
        return 1;
    }

    fn deinit(self: *Neg) void {
        allo.destroy(self);
    }
};

pub fn sin() !Block {
    return Block{
        .sin = try Sin.init(),
    };
}

const Sin = struct {
    fn init() !*Sin {
        return try allo.create(Sin);
    }

    fn eval(self: *Sin, now: u64, input: []f32, output: []f32) void {
        _ = self;
        const freq = input[0];
        const phase = @mod(freq * time(now), 1.0);
        output[0] = @floatCast(@sin(phase * std.math.tau));
    }

    fn in(self: *Sin) usize {
        _ = self;
        return 1;
    }

    fn out(self: *Sin) usize {
        _ = self;
        return 1;
    }

    fn deinit(self: *Sin) void {
        allo.destroy(self);
    }
};

pub fn val(value: f32) !Block {
    return Block{
        .val = try Val.init(value),
    };
}

const Val = struct {
    value: f32,

    fn init(value: f32) !*Val {
        var v = try allo.create(Val);
        errdefer allo.destroy(v);
        v.value = value;
        return v;
    }

    fn eval(self: *Val, now: u64, input: []f32, output: []f32) void {
        _ = input;
        _ = now;
        output[0] = self.value;
    }

    fn in(self: *Val) usize {
        _ = self;
        return 0;
    }

    fn out(self: *Val) usize {
        _ = self;
        return 1;
    }

    fn deinit(self: *Val) void {
        allo.destroy(self);
    }
};

pub fn id() !Block {
    return Block{
        .id = try Id.init(),
    };
}

const Id = struct {
    fn init() !*Id {
        var i = try allo.create(Id);
        errdefer allo.destroy(i);
        return i;
    }

    fn eval(self: *Id, now: u64, input: []f32, output: []f32) void {
        _ = now;
        _ = self;
        output[0] = input[0];
    }

    fn in(self: *Id) usize {
        _ = self;
        return 1;
    }

    fn out(self: *Id) usize {
        _ = self;
        return 1;
    }

    fn deinit(self: *Id) void {
        allo.destroy(self);
    }
};

test "identity function" {
    try init(std.testing.allocator, 48000, 1, 1);
    defer deinit();
    var i = try id();
    defer i.deinit();
    in[0] = 42;
    i.eval(0, in, out);
    try expect(out[0] == in[0]);
}

/// single cycle waveform, passing data
pub fn wave(data: []f32) !Block {
    return Block{
        .wave = try Wave.init(data),
    };
}

const wavegen = *const fn (phase: f32) f32;

/// single cycle waveform, generating data from a function
pub fn wavefn(len: usize, gen: wavegen) !Block {
    var w = allo.alloc(f32, len);
    for (0..len) |i| {
        const phase = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(len));
        w[i] = gen(phase);
    }

    return Block{
        .wave = try Wave.init(w),
    };
}

/// single cycle waveform
const Wave = struct {
    data: []f32,

    fn init(data: []f32) !*Wave {
        var w = try allo.create(Wave);
        errdefer allo.destroy(w);

        w.data = data;
        return w;
    }

    fn eval(self: *Wave, now: u64, input: []f32, output: []f32) void {
        const freq = input[0];
        const phase = @as(f32, @floatFromInt(now)) / @as(f32, @floatFromInt(srate)) * freq;
        output[0] = interpolate0(self.data, phase);
    }

    fn in(self: *Wave) usize {
        _ = self;
        return 1; // freq
    }

    fn out(self: *Wave) usize {
        _ = self;
        return 1; // signal
    }

    fn deinit(self: *Wave) void {
        allo.free(self.data);
        allo.destroy(self);
    }
};

/// No interpolation, return the closest value from data, rounded toward zero
fn interpolate0(data: []f32, phase: f64) f32 {
    const len = @as(f64, @floatFromInt(data.len));
    const index = @as(usize, @intFromFloat(@trunc(phase * len)));
    return data[index];
}

/// get time in seconds from time in samples
inline fn time(now: u64) f64 {
    return @as(f64, @floatFromInt(now)) / @as(f64, @floatFromInt(srate));
}
