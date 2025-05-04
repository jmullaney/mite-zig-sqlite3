const std = @import("std");
const mite = @import("mite.zig");
const c = @cImport({
    @cInclude("sqlite3.h");
});
const helper = @import("test-helper.zig");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;
const allocator = std.testing.allocator;
fn discard(_: anytype) void {}

// Value.init - int

test "Value.init signed int <= 32 bits -> .INTEGER" {
    const v1: i32 = 127;
    const m3_value1 = try mite.Value.init(v1);
    try expectEqual(127, m3_value1.INTEGER);

    const v2: i16 = 321;
    const m3_value2 = try mite.Value.init(v2);
    try expectEqual(321, m3_value2.INTEGER);
}

test "Value.init unsigned int < 32 bits -> .INTEGER" {
    const v1: u16 = 127;
    const m3_value1 = try mite.Value.init(v1);
    try expectEqual(127, m3_value1.INTEGER);

    const v2: u31 = 321;
    const m3_value2 = try mite.Value.init(v2);
    try expectEqual(321, m3_value2.INTEGER);
}

test "Value.init signed int > 32 bits and <= 64 bits -> .INTEGER" {
    const v1: i64 = 127;
    const m3_value1 = try mite.Value.init(v1);
    try expectEqual(127, m3_value1.INTEGER);

    const v2: i33 = 321;
    const m3_value2 = try mite.Value.init(v2);
    try expectEqual(321, m3_value2.INTEGER);
}

test "Value.init unsigned int >= 32 bits and < 64 bits -> .INTEGER" {
    const v1: u32 = 127;
    const m3_value1 = try mite.Value.init(v1);
    try expectEqual(127, m3_value1.INTEGER);

    const v2: u63 = 321;
    const m3_value2 = try mite.Value.init(v2);
    try expectEqual(321, m3_value2.INTEGER);
}

test "Value.init signed int > 64 bits or unsigned int >= 64 bits that fits in i64 -> .INTEGER" {
    const v1: i128 = 127;
    const m3_value1 = try mite.Value.init(v1);
    try expectEqual(127, m3_value1.INTEGER);

    const v2: i128 = std.math.pow(i128, 2, 63) - 1;
    const m3_value2 = try mite.Value.init(v2);
    try expectEqual(9223372036854775807, m3_value2.INTEGER);

    const v3: u64 = std.math.pow(u64, 2, 63) - 1;
    const m3_value3 = try mite.Value.init(v3);
    try expectEqual(9223372036854775807, m3_value3.INTEGER);
}

test "Value.init signed int > 64 bits or unsigned int >= 64 bits that does not fit in i64 -> Error.NumberTooLarge" {
    const v1 = std.math.pow(i128, 2, 63);
    const m3_value_eu = mite.Value.init(v1);
    try expectError(mite.Error.NumberTooLarge, m3_value_eu);

    const v2 = std.math.pow(u64, 2, 63) + 2;
    const m3_value_eu2 = mite.Value.init(v2);
    try expectError(mite.Error.NumberTooLarge, m3_value_eu2);
}

// Value.init - comptime_int

test "Value.init comptime_int fitting in i32 -> .INTEGER" {
    const m3_value1 = try mite.Value.init(45);
    try expectEqual(45, m3_value1.INTEGER);
}

test "Value.init comptime_int fitting in i64 -> .INTEGER" {
    const m3_value1 = try mite.Value.init(8_000_000_001);
    try expectEqual(8_000_000_001, m3_value1.INTEGER);
}

test "Value.init comptime_int not fitting i64 -> Error.NumberTooLarge" {
    const m3_value_eu = mite.Value.init(64_123_456_786_000_000_001);
    try expectError(mite.Error.NumberTooLarge, m3_value_eu);

    const v2 = comptime @as(u64, @intCast(std.math.maxInt(i64))) + 1;
    const m3_value_eu2 = mite.Value.init(v2);
    try expectError(mite.Error.NumberTooLarge, m3_value_eu2);
}

// Value.init - float

test "Value.init float with <= 64 bits -> .FLOAT" {
    const v1: f64 = 123.456;
    const m3_value1 = try mite.Value.init(v1);
    try expectEqual(123.456, m3_value1.FLOAT);

    const v2: f32 = 1.0 / 3.0;
    const m3_value2 = try mite.Value.init(v2);
    try expectEqual(@as(f64, @floatCast(@as(f32, 1.0 / 3.0))), m3_value2.FLOAT);
}

test "Value.init float with > 64 bits that fits in f64 without loss of precision -> .FLOAT" {
    const v1: f128 = 123.25;
    const m3_value1 = try mite.Value.init(v1);
    try expectEqual(123.25, m3_value1.FLOAT);
}

test "Value.init float that loses precision when converted to f64 -> Error,NumberTooLarge" {
    const v1: f128 = 1.0 / 3.0;
    const m3_value_eu = mite.Value.init(v1);
    try expectError(mite.Error.NumberTooLarge, m3_value_eu);
}

// Value.init - comptime_float

test "Value.init comptime_float that doesn't lose precision as f64 -> .FLOAT" {
    const m3_value1 = try mite.Value.init(123.25);
    try expectEqual(123.25, m3_value1.FLOAT);
}

test "Value.init comptime_float that loses precision as f64 -> Error.NumberTooLarge" {
    const m3_value_eu = mite.Value.init(1.0 / 3.0);
    try expectError(mite.Error.NumberTooLarge, m3_value_eu);
}

// Value.init - bool

test "Value.init true -> .INTEGER 1" {
    const m3_value1 = try mite.Value.init(true);
    try expectEqual(1, m3_value1.INTEGER);

    const v2 = true;
    const m3_value2 = try mite.Value.init(v2);
    try expectEqual(1, m3_value2.INTEGER);
}

test "Value.init false -> .INTEGER 0" {
    const m3_value1 = try mite.Value.init(false);
    try expectEqual(0, m3_value1.INTEGER);

    const v2 = false;
    const m3_value2 = try mite.Value.init(v2);
    try expectEqual(0, m3_value2.INTEGER);
}

// Value.init - enum
// (binds using enum int value, following int rules)

test "Value.init enum with signed int <= 32 bits or unsigned int with < 32 bits -> .INTEGER" {
    const tenum = enum { fawn, red, white, black, brindle, blue };
    const m3_value1 = try mite.Value.init(tenum.brindle);
    try expectEqual(4, m3_value1.INTEGER);

    const tenum2 = enum(u16) { fawn = 10, red, white, black, brindle, blue };
    const m3_value2 = try mite.Value.init(tenum2.brindle);
    try expectEqual(14, m3_value2.INTEGER);
}

test "Value.init enum with signed int <= 64 bits or unsigned int with < 64 bits -> .INTEGER" {
    const tenum = enum(i64) { fawn = 2147483645, red, white, black, brindle, blue };
    const m3_value1 = try mite.Value.init(tenum.brindle);
    try expectEqual(2147483649, m3_value1.INTEGER);

    const tenum2 = enum(u32) { fawn = 10, red, white, black, brindle, blue };
    const m3_value2 = try mite.Value.init(tenum2.brindle);
    try expectEqual(14, m3_value2.INTEGER);
}

test "Value.init enum with signed int > 64 bits or unsigned int >= 64 bits that fits in i64 -> .INTEGER" {
    const tenum = enum(i128) { fawn = 9_223_372_036_854_775_800, red, white, black, brindle, blue };
    const m3_value1 = try mite.Value.init(tenum.brindle);
    try expectEqual(9_223_372_036_854_775_804, m3_value1.INTEGER);

    const tenum2 = enum(u64) { fawn = 10, red, white, black, brindle, blue };
    const m3_value2 = try mite.Value.init(tenum2.brindle);
    try expectEqual(14, m3_value2.INTEGER);
}

test "Value.init enum with signed int > 64 bits or unsigned int >= 64 bits that does not fit in i64 -> Error.NumberTooLarge" {
    const tenum = enum(i128) { fawn = 9_223_372_036_854_775_808, red, white, black, brindle, blue };
    const m3_value_eu = mite.Value.init(tenum.brindle);
    try expectError(mite.Error.NumberTooLarge, m3_value_eu);

    const tenum2 = enum(u64) { fawn = 9_223_372_036_854_775_810, red, white, black, brindle, blue };
    const m3_value_eu2 = mite.Value.init(tenum2.brindle);
    try expectError(mite.Error.NumberTooLarge, m3_value_eu2);
}

// Value.init - sentinal terminated array value (not pointer to array)

test "Value.init array u8 does not compile" {
    try helper.verifyCompilerError(.{
        .allocator = allocator,
        .test_code =
        \\ const v1 = [3:0]u8{ '3', '2', '1' };
        \\ _ = try mite.Value.init(v1);
        \\ const v2 = [3:1]u8{ '4', '3', '2' };
        \\ _ = try mite.Value.init(v2);
        \\ const v3 = [3]u8{ '3', '2', '1' };
        \\ _ = try mite.Value.init(v3);
        ,
        .expected_error = "error: array type not supported binding one parameter",
        .expected_count = 3,
    });
}

test "Value.init array non-u8 does not compile" {
    try helper.verifyCompilerError(.{
        .allocator = allocator,
        .test_code =
        \\ const v1 = [3:0]u16{ 3333, 2222, 1111 };
        \\ _ = try mite.Value.init(v1);
        \\ const v2 = [3:1]u16{ 4444, 3333, 2222 };
        \\ _ = try mite.Value.init(v2);
        \\ const v3 = [3]u4{ 3, 2, 1 };
        \\ _ = try mite.Value.init(v3);
        ,
        .expected_error = "error: array type not supported binding one parameter",
        .expected_count = 3,
    });
}

test "Value.init pointer to array of u8 -> .BLOB comprising the entire array" {}

test "Value.init pointer to null-terminated array of u8 -> .TEXT comprising characters up-to the first terminator" {}

test "Value.init pointer to sentinal-terminated array of u8, where terminator is non-0 -> .BLOB comprising characters up-to the first terminator" {}

test "Value.init pointer to array of non-u8 does not compile" {
    // not-sentinal terminated
    // null terminated
    // terminated, sentinal not 0
}

test "Value.init null-terminated pointer to many u8 -> .TEXT" {}

test "Value.init sentinal-terminated pointer to many u8, where terminator is non-0 -> .BLOB" {}

test "Value.init null-terminated C pointer to u8 -> .TEXT" {}

test "Value.init sentinal-terminated C pointer to u8, where terminator is non-0 -> .BLOB" {}

test "Value.init C pointer to non-u8 does not compile" {
    // not-sentinal terminated
    // null terminated
    // terminated, sentinal not 0
}

// test "aaaa" {
//     const v1 = [3:0]u8{ '3', '2', '1' };
//     _ = try mite.Value.init(v1);

//     const v2 = [3:1]u8{ '4', '3', '2' };
//     _ = try mite.Value.init(v2);
// }

// test "Value.init [_:0]u8 and [_:0]const u8 -> .TEXT" {
//     var v1 = [9:0]u8{ '1', '2', '3', '0', '5', '6', '7', '8', '9' };
//     v1[3] = '4';
//     const m3_value1 = try mite.Value.init(v1);
//     try expectEqualStrings("123456789", m3_value1.TEXT);

//     const v2 = [9:0]u8{ '1', '2', '3', '4', '5', '6', '7', '8', '9' };
//     const m3_value2 = try mite.Value.init(v2);
//     try expectEqualStrings("123456789", m3_value2.TEXT);
// }

// test "Value.init [_:(non-0)]u8 and [_:(non-0)]const u8 -> .BLOB" {
//     var v1 = [9:0xff]u8{ '1', '2', '3', '0', '5', '6', '7', '8', '9' };
//     v1[3] = '4';
//     const m3_value1 = try mite.Value.init(v1);
//     try expectEqualStrings("123456789", m3_value1.BLOB);

//     const v2 = [9:1]u8{ '1', '2', '3', '4', '5', '6', '7', '8', '9' };
//     const m3_value2 = try mite.Value.init(v2);
//     try expectEqualStrings("123456789", m3_value2.BLOB);
// }

// test "Value.init sentinal-terminated array non-u8 does not compile" {
//     try helper.verifyCompilerError(.{
//         .allocator = allocator,
//         .test_code =
//         \\ const v1: [2:0]u16 = [_:0]u16{ 74, 1024 };
//         \\ _ = try mite.Value.init(v1); // DOES NOT COMPILE
//         \\ discard(v1);
//         \\ const v2: [2:1]u16 = [_:1]u16{ 3, 2 };
//         \\ _ = try mite.Value.init(v2); // DOES NOT COMPILE
//         \\ discard(v2);
//         ,
//         .expected_error = "error: array type not supported binding one parameter",
//         .expected_count = 2,
//     });
//     //  allocator, "test",
//     // , "array type not supported binding one parameter", 2);
// }

// Value.init - array

test "Value.init array of u8 does not compile" {
    const v1 = [_]u8{ 65, 66, 67 };
    // _ = try mite.Value.init(v1); // DOES NOT COMPILE
    discard(v1);
}

test "Value.init array of non-u8 does not compile" {
    const v1 = [_]u16{ 74, 6543 };
    // _ = try mite.Value.init(v1); // DOES NOT COMPILE
    discard(v1);
}

// Value.init - slice

test "Value.init []u8 and []const u8 -> .TEXT" {
    const v1: []const u8 = "apple sauce";
    const m3_value1 = try mite.Value.init(v1);
    try expectEqualStrings("apple sauce", m3_value1.TEXT);

    const v2: []u8 = try std.fmt.allocPrint(allocator, "{s} and cinnamon", .{v1});
    defer allocator.free(v2);
    const m3_value2 = try mite.Value.init(v2);
    try expectEqualStrings("apple sauce and cinnamon", m3_value2.TEXT);
}

test "Value.init slice of non u8 does not compile" {
    const v1 = [_]u16{ 74, 1024 };
    const v2 = @as([]const u16, &v1);
    // _ = try mite.Value.init(v2); // DOES NOT COMPILE
    discard(v2);
}

// Value.init - null

test "Value.init null -> .NULL" {
    const m3_value1 = try mite.Value.init(null);
    try expectEqual(mite.Value.NULL, m3_value1);
}

// Value.init - optional

test "Value.init - null optional -> .NULL" {
    const v1: ?u16 = null;
    const m3_value1 = try mite.Value.init(v1);
    try expectEqual(mite.Value.NULL, m3_value1);

    const v2: ?i64 = null;
    const m3_value2 = try mite.Value.init(v2);
    try expectEqual(mite.Value.NULL, m3_value2);

    const v3: ?f32 = null;
    const m3_value3 = try mite.Value.init(v3);
    try expectEqual(mite.Value.NULL, m3_value3);

    const v4: ?[]u8 = null;
    const m3_value4 = try mite.Value.init(v4);
    try expectEqual(mite.Value.NULL, m3_value4);
}

test "Value.init non-null optional -> Value type for the underlying type" {
    const v1: ?u16 = 765;
    const m3_value1 = try mite.Value.init(v1);
    try expectEqual(765, m3_value1.INTEGER);

    const v2: ?i64 = 998866;
    const m3_value2 = try mite.Value.init(v2);
    try expectEqual(998866, m3_value2.INTEGER);

    const v3: ?f32 = 999.75;
    const m3_value3 = try mite.Value.init(v3);
    try expectEqual(999.75, m3_value3.FLOAT);

    const v4: ?[]const u8 = "light roast coffee";
    const m3_value4 = try mite.Value.init(v4);
    try expectEqualStrings("light roast coffee", m3_value4.TEXT);
}

// Value.init - pointer to one

test "Value.init pointer to one except u8 array -> Value type for the underlying type" {
    const v1: u16 = 765;
    const v1_ptr = &v1;
    const m3_value1 = try mite.Value.init(v1_ptr);
    try expectEqual(765, m3_value1.INTEGER);

    const v2: ?i64 = 998866;
    const v2_ptr = &v2;
    const m3_value2 = try mite.Value.init(v2_ptr);
    try expectEqual(998866, m3_value2.INTEGER);

    const v3: ?f32 = 999.75;
    const v3_ptr = &v3;
    const m3_value3 = try mite.Value.init(v3_ptr);
    try expectEqual(999.75, m3_value3.FLOAT);

    const v4: ?[]const u8 = "light roast coffee";
    const v4_ptr = &v4;
    const m3_value4 = try mite.Value.init(v4_ptr);
    try expectEqualStrings("light roast coffee", m3_value4.TEXT);
}

test "Value.init pointer to one u8 array -> .TEXT" {
    const v1 = "laser beam";
    const m3_value1 = try mite.Value.init(v1);
    try expectEqualStrings("laser beam", m3_value1.TEXT);

    // make sure test case setup is correct
    try expect(@typeInfo(@TypeOf(v1)) == .pointer);
    try expect(@typeInfo(@typeInfo(@TypeOf(v1)).pointer.child) == .array);
    try expect(@typeInfo(@typeInfo(@TypeOf(v1)).pointer.child).array.child == u8);
}

test "Value.init pointer to one non-u8 array does not compile" {
    const v1 = &[_]u16{ 65535, 1, 0, 9 };
    // _ = try mite.Value.init(v1); // DOES NOT COMPILE
    discard(v1);

    // make sure test case setup is correct
    try expect(@typeInfo(@TypeOf(v1)) == .pointer);
    try expect(@typeInfo(@typeInfo(@TypeOf(v1)).pointer.child) == .array);
    try expect(@typeInfo(@typeInfo(@TypeOf(v1)).pointer.child).array.child == u16);
}

// Value.init - pointer to many

test "Value.init pointer to many does not compile" {
    const v1 = &[_]u16{ 65535, 1, 0, 9 };
    const v1_ptr_to_many: [*]const u16 = @ptrCast(v1);
    // _ = try mite.Value.init(v1_ptr_to_many); // DOES NOT COMPILE
    discard(v1_ptr_to_many);

    // make sure test case setup is correct
    try expect(@typeInfo(@TypeOf(v1_ptr_to_many)) == .pointer);
    try expect(@typeInfo(@TypeOf(v1_ptr_to_many)).pointer.size == .many);
}

// Value.init - c pointer

test "Value.init c pointer does not compile" {
    const v1 = &[_]u16{ 65535, 1, 0, 9 };
    const v1_ptr_to_many: [*c]const u16 = @ptrCast(v1);
    // _ = try mite.Value.init(v1_ptr_to_many); // DOES NOT COMPILE
    discard(v1_ptr_to_many);

    // make sure test case setup is correct
    try expect(@typeInfo(@TypeOf(v1_ptr_to_many)) == .pointer);
    try expect(@typeInfo(@TypeOf(v1_ptr_to_many)).pointer.size == .c);
}

// Value.init - tagged union

test "Value.init tagged union binds the value of the active tag using appropriate sqlite3_bind_* function" {
    const TU = union(enum) {
        int: i32,
        int64: i64,
        double: f64,
        text: []const u8,
        optInt: ?i32,
    };

    const v1 = TU{ .int = 65 };
    const m3_value1 = try mite.Value.init(v1);
    try expectEqual(65, m3_value1.INTEGER);

    const v2 = TU{ .int64 = 164 };
    const m3_value2 = try mite.Value.init(v2);
    try expectEqual(164, m3_value2.INTEGER);

    const v3 = TU{ .double = 876.5 };
    const m3_value3 = try mite.Value.init(v3);
    try expectEqual(876.5, m3_value3.FLOAT);

    const v4 = TU{ .text = "roaring lions" };
    const m3_value4 = try mite.Value.init(v4);
    try expectEqualStrings("roaring lions", m3_value4.TEXT);

    const v5 = TU{ .optInt = null };
    const m3_value5 = try mite.Value.init(v5);
    try expectEqual(mite.Value.NULL, m3_value5);

    const v6 = TU{ .optInt = 72 };
    const m3_value6 = try mite.Value.init(v6);
    try expectEqual(72, m3_value6.INTEGER);
}

test "Value.init tagged union works correctly when tag values are sparse" {
    const SparseTag = enum(i32) {
        tag0,
        tag2 = 2,
        tag100 = 100,
    };

    const TU = union(SparseTag) {
        tag0: i32,
        tag2: i64,
        tag100: f64,
    };

    const v1 = TU{ .tag0 = 65 };
    const m3_value1 = try mite.Value.init(v1);
    try expectEqual(65, m3_value1.INTEGER);

    const v2 = TU{ .tag2 = 164 };
    const m3_value2 = try mite.Value.init(v2);
    try expectEqual(164, m3_value2.INTEGER);

    const v3 = TU{ .tag100 = 876.5 };
    const m3_value3 = try mite.Value.init(v3);
    try expectEqual(876.5, m3_value3.FLOAT);
}

// Value.init - untagged union

test "Value.init untagged union does not compile" {
    const U = union {
        int: i32,
        int64: i64,
    };
    const v1 = U{ .int = 44 };
    // _ = try mite.Value.init(v1); // DOES NOT COMPILE
    discard(v1);
}

// Value.init - struct

test "bindOneParameter struct does not compile" {
    const v1 = struct { x: i64, y: i64 }{ .x = 30, .y = 45 };
    // _ = try mite.Value.init(v1); // DOES NOT COMPILE
    discard(v1);
}

// Value.init - other

test "Value.init other types do not compile" {
    // opaque pointer
    const v1 = 47;
    const v1_opaque_ptr = @as(*const anyopaque, &v1);
    // _ = try mite.Value.init(v1_opaque_ptr); // DOES NOT COMPILE
    discard(v1_opaque_ptr);

    // enum literal
    const v2_enum_lit_value = .abc;
    // _ = try mite.Value.init(v2_enum_lit_value); // DOES NOT COMPILE
    discard(v2_enum_lit_value);

    // Frame
    // AnyFrame
    // Vector
    // Fn
    // ErrorSet
    // ErrorUnion
    // Undefined
    // NoReturn
    // Void
}
