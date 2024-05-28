const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const Tuple = std.meta.Tuple;

/// check if two tuple types are identical
pub fn eq(comptime A: type, comptime B: type) bool {
    // TODO check A and B are tuples
    const fa = std.meta.fields(A);
    const fb = std.meta.fields(B);
    if (fa.len != fb.len) {
        return false;
    }
    inline for (fa, fb) |a, b| {
        if (a.type != b.type) {
            return false;
        }
    }
    return true;
}

test "eq" {
    const A = struct { f32, u8 };
    const B = struct { f32, u8 };
    const C = struct { u8, f32 };
    const D = struct { u8 };
    try expect(eq(A, A));
    try expect(eq(A, B));
    try expect(!eq(A, C));
    try expect(!eq(A, D));
}

/// returns the length of a tuple type
pub fn len(comptime A: type) usize {
    return std.meta.fields(A).len;
}

test "len" {
    const A = struct { u8, f32 };
    const B = struct { u8 };
    try expectEqual(2, len(A));
    try expectEqual(1, len(B));
}

/// concatenate two tuple types
pub fn Join(A: type, B: type) type {
    const a: A = undefined;
    const b: B = undefined;
    return @TypeOf(a ++ b);
}

test "Join" {
    const A = struct { f32 = 0 };
    const B = struct { u8 = 0, bool = false };
    const AB = Join(A, B);
    const ab: AB = undefined;
    try expectEqual(3, ab.len);
    try expectEqual(f32, @TypeOf(ab[0]));
    try expectEqual(u8, @TypeOf(ab[1]));
    try expectEqual(bool, @TypeOf(ab[2]));
}

/// split a tuple type in two at pivot point
pub fn Split(T: type, pivot: usize) type {
    const fields = std.meta.fields(T);
    std.debug.assert(pivot <= fields.len);
    var types_a: [pivot]type = undefined;
    var types_b: [fields.len - pivot]type = undefined;
    for (fields, 0..) |f, i| {
        if (i < pivot) {
            types_a[i] = f.type;
        } else {
            types_b[i - pivot] = f.type;
        }
    }
    const Tuple_a = Tuple(&types_a);
    const Tuple_b = Tuple(&types_b);
    return struct { Tuple_a, Tuple_b };
}

test "Split" {
    const AB = Split(struct { f32, u8, bool }, 1);
    const ab: AB = undefined;
    try expectEqual(1, ab[0].len);
    try expectEqual(2, ab[1].len);
    try expectEqual(f32, @TypeOf(ab[0][0]));
    try expectEqual(u8, @TypeOf(ab[1][0]));
    try expectEqual(bool, @TypeOf(ab[1][1]));
}

/// split a tuple at pivot point
pub fn split(tuple: anytype, comptime pivot: usize) Split(@TypeOf(tuple), pivot) {
    var sp: Split(@TypeOf(tuple), pivot) = undefined;
    inline for (tuple, 0..) |value, index| {
        if (index < pivot) {
            sp[0][index] = value;
        } else {
            sp[1][index - pivot] = value;
        }
    }
    return sp;
}

test "split" {
    const tuple: struct { u8, f32, bool } = .{ 1, 2, false };
    const sp = split(tuple, 1);
    try expectEqual(@as(u8, 1), sp[0][0]);
    try expectEqual(@as(f32, 2), sp[1][0]);
    try expectEqual(@as(bool, false), sp[1][1]);
}
