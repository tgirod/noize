const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const Tuple = std.meta.Tuple;

pub fn Slice(comptime T: type, start: usize, end: usize) type {
    const fields = std.meta.fields(T);
    std.debug.assert(start <= end);
    std.debug.assert(end <= fields.len);
    var types: [end - start]type = undefined;
    for (fields[start..end], 0..) |field, i| {
        types[i] = field.type;
    }
    return Tuple(&types);
}

test "Slice" {
    const T = struct { f32, u8, bool };
    {
        const s: Slice(T, 0, 2) = undefined;
        try expectEqual(2, s.len);
        try expectEqual(f32, @TypeOf(s[0]));
        try expectEqual(u8, @TypeOf(s[1]));
    }
    {
        const s: Slice(T, 1, 3) = undefined;
        try expectEqual(2, s.len);
        try expectEqual(u8, @TypeOf(s[0]));
        try expectEqual(bool, @TypeOf(s[1]));
    }
    {
        const s: Slice(T, 1, 1) = undefined;
        try expectEqual(0, s.len);
    }
}

pub fn slice(tuple: anytype, comptime start: usize, comptime end: usize) Slice(@TypeOf(tuple), start, end) {
    var result: Slice(@TypeOf(tuple), start, end) = undefined;
    inline for (start..end) |i| {
        result[i - start] = tuple[i];
    }
    return result;
}

test "slice" {
    const t: struct { f32, u8, bool } = .{ 1, 2, false };
    {
        const s = slice(t, 0, 2);
        try expectEqual(.{ @as(f32, 1), @as(u8, 2) }, s);
    }
    {
        const s = slice(t, 1, 2);
        try expectEqual(.{@as(u8, 2)}, s);
    }
    {
        const s = slice(t, 1, 1);
        try expectEqual(.{}, s);
    }
}

/// check if two tuple types are identical
pub fn typematch(comptime A: type, comptime B: type) bool {
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

test "typematch" {
    const A = struct { f32, u8 };
    const B = struct { f32, u8 };
    const C = struct { u8, f32 };
    const D = struct { u8 };
    try expect(typematch(A, A));
    try expect(typematch(A, B));
    try expect(!typematch(A, C));
    try expect(!typematch(A, D));
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
