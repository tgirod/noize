const n = @import("./root.zig");

const srate = 48000;

const Root = n.Id(2);

var back: n.jack.Client(Root) = undefined;

pub fn main() !void {
    try back.init("noize");
    try back.connect();
    try back.activate();
    try back.deactivate();
    back.deinit();
}
