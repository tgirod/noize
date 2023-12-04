const std = @import("std");
const comptimePrint = std.fmt.comptimePrint;
const builtin = std.builtin;

/// identity function
fn Id(comptime T: type) type {
    return struct {
        pub const Input = struct {
            in: T,
        };

        pub const Output = struct {
            out: T,
        };

        const Self = @This();
        fn eval(self: *Self, input: Self.Input) Self.Output {
            _ = self;
            return .{ .out = input.in };
        }
    };
}

/// connect two blocks as a sequence
fn Seq(comptime A: type, comptime B: type) type {
    for (std.meta.fields(A.Output), std.meta.fields(B.Input)) |p, n| {
        if (p.type != n.type) {
            const msg = comptimePrint(
                "{s}({any}) != {s}({any}) : type mismatch",
                .{ p.name, p.type, n.name, n.type },
            );
            @compileError(msg);
        }
    }

    return struct {
        prev: A = A{},
        next: B = B{},

        pub const Input = A.Input;
        pub const Output = B.Output;

        const Self = @This();

        fn eval(self: *Self, input: Self.Input) Self.Output {
            var out = self.prev.eval(input);
            var cast: *B.Input = @ptrCast(@alignCast(&out));
            return self.next.eval(cast.*);
        }
    };
}

fn Par(comptime A: type, comptime B: type) type {
    // input fields
    const input_a = std.meta.fields(A.Input);
    const input_b = std.meta.fields(B.Input);
    comptime var input_fields: [input_a.len + input_b.len]builtin.Type.StructField = undefined;

    for (input_a, 0..) |f, i| {
        input_fields[i] = .{
            .name = f.name ++ ".a",
            .type = f.type,
            .default_value = f.default_value,
            .is_comptime = f.is_comptime,
            .alignment = f.alignment,
        };
    }
    for (input_b, input_a.len..) |f, i| {
        input_fields[i] = .{
            .name = f.name ++ ".b",
            .type = f.type,
            .default_value = f.default_value,
            .is_comptime = f.is_comptime,
            .alignment = f.alignment,
        };
    }

    // output fields
    const output_a = std.meta.fields(A.Output);
    const output_b = std.meta.fields(B.Output);
    comptime var output_fields: [output_a.len + output_b.len]builtin.Type.StructField = undefined;

    for (output_a, 0..) |f, i| {
        output_fields[i] = .{
            .name = f.name ++ ".a",
            .type = f.type,
            .default_value = f.default_value,
            .is_comptime = f.is_comptime,
            .alignment = f.alignment,
        };
    }
    for (output_b, output_a.len..) |f, i| {
        output_fields[i] = .{
            .name = f.name ++ ".b",
            .type = f.type,
            .default_value = f.default_value,
            .is_comptime = f.is_comptime,
            .alignment = f.alignment,
        };
    }

    return struct {
        a: A = A{},
        b: B = B{},

        pub const Input = @Type(.{
            .Struct = .{
                .layout = .Auto,
                .fields = &input_fields,
                .decls = &[_]builtin.Type.Declaration{},
                .is_tuple = false,
            },
        });

        pub const Output = @Type(.{
            .Struct = .{
                .layout = .Auto,
                .fields = &output_fields,
                .decls = &[_]builtin.Type.Declaration{},
                .is_tuple = false,
            },
        });

        const Self = @This();

        fn eval(self: *Self, input: Self.Input) Self.Output {
            // split Self.Input into A.Input and B.Input

            // var input_a: A.Input = undefined;
            // var input_b: B.Input = undefined;
            // eval a and b
            // concat a.Output and b.Output into Self.Output

            _ = input;
            _ = self;
            // TODO
        }
    };
}

pub fn main() void {
    const Tree = Par(Id(f32), Id(u32));
    var t = Tree{};
    _ = t;
    std.debug.print(
        \\ input: {any}
        \\ output: {any}
    , .{ Tree.Input, Tree.Output });
    // const in: Tree.Input = .{ .in = 23 };
    // const out = t.eval(in);
    // std.debug.print("{}\n", .{out});
}
