const std = @import("std");
const n = @import("noize.zig");

pub fn main() !void {
    var tree = n.Noize(
        2,
        [_]n.Kind{ .float, .float },
        1,
        [_]n.Kind{.float},
        n.Add(.float),
    ){};

    tree.input[0].float = 100;
    tree.input[1].float = 100;
    tree.eval();
    std.debug.print(
        \\ {any}
        \\ {any}
    , .{ tree.input, tree.output });

    // for (0..480) |index| {
    //     root.eval(@as(u64, index), n.in, n.out);
    //     std.debug.print("{any} {any}\n", .{ n.out[0], n.out[1] });
    // }
}
