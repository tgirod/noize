const std = @import("std");

fn Id(comptime t: type) type {
    return struct {
        pub const Input = [1]type{t};
        pub const Output = [1]type{t};

        pub fn eval(self: *@This(), input: std.meta.Tuple(&Input)) std.meta.Tuple(&Output) {
            _ = self;
            return .{input[0]};
        }
    };
}

fn Par(comptime A: type, comptime B: type) type {
    return struct {
        pub const Input = A.Input ++ B.Input;
        pub const Output = A.Output ++ B.Output;
        a: A = A{},
        b: B = B{},

        pub fn eval(self: *@This(), input: std.meta.Tuple(&Input)) std.meta.Tuple(&Output) {
            var input_a: std.meta.Tuple(&A.Input) = undefined;
            var input_b: std.meta.Tuple(&B.Input) = undefined;
            inline for (input, 0..) |v, i| {
                if (i < input_a.len) {
                    input_a[i] = v;
                } else {
                    input_b[i - input_a.len] = v;
                }
            }
            return self.a.eval(input_a) ++ self.b.eval(input_b);
        }
    };
}

fn Seq(comptime A: type, comptime B: type) type {
    if (!std.mem.eql(type, &A.Output, &B.Input)) {
        @compileError("mismatch");
    }

    return struct {
        pub const Input = A.Input;
        pub const Output = B.Output;
        a: A = A{},
        b: B = B{},

        pub fn eval(self: *@This(), input: std.meta.Tuple(&Input)) std.meta.Tuple(&Output) {
            return self.b.eval(self.a.eval(input));
        }
    };
}

fn Add(comptime t: type) type {
    return struct {
        pub const Input = [2]type{ t, t };
        pub const Output = [1]type{t};

        pub fn eval(self: *@This(), input: std.meta.Tuple(&Input)) std.meta.Tuple(&Output) {
            _ = self;
            return .{input[0] + input[1]};
        }
    };
}

pub fn main() void {
    // var root = Add(i64){};
    // var o = root.eval(.{ 23, 42 });
    // std.debug.print(
    //     \\ {any}
    //     \\ {any}
    // , .{ root, o });

    // var t1 = .{ @as(u8, 23), @as(u16, 42) };
    // var t2 = t1 ++ t1;
    // var t3 = t2[0..2];
    // std.debug.print(
    //     \\ {any}
    //     \\ {any}
    // , .{ t2, t3 });

    // var x: std.meta.Tuple(&Add(bool).Input) = undefined;
    // x[0] = true;
    // x[1] = false;
    // std.debug.print(
    //     \\ {any}
    // , .{x});

    var root = Par(Id(u8), Id(u8)){};
    var o = root.eval(.{ 1, 2 });
    std.debug.print(
        \\ {any}
    , .{o});
}
