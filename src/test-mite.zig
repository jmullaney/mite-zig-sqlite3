const std = @import("std");
const mite = @import("mite.zig");
const c = @cImport({
    @cInclude("sqlite3.h");
});
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;
const allocator = std.testing.allocator;
fn discard(_: anytype) void {}

test {
    _ = @import("test-Value init.zig");
}

test "basic test" {
    const TestRow = struct {
        id: i64,
        name: []const u8,
    };

    var db: ?*c.sqlite3 = null;
    try mite.ok(c.sqlite3_open(":memory:", &db));
    defer _ = c.sqlite3_close(db);

    try mite.run(db, "CREATE TABLE test (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)", .{});
    try mite.run(db, "INSERT INTO test(name) VALUES (?), (?), (?), (?)", .{ "aaa", "bbb2", "ccc", "aaa2" });

    {
        var it = try mite.exec(TestRow, db, "SELECT id, name FROM test WHERE id = ?", 4);
        defer it.deinit();
        if (try it.next()) |row1| {
            try expectEqual(4, row1.id);
            try expectEqualStrings("aaa2", row1.name);
        } else {
            std.log.err("should return row", .{});
        }
        if (try it.next()) |_| {
            std.log.err("should not return a second row", .{});
        }
    }

    {
        var it = try mite.exec(TestRow, db, "SELECT id, name FROM test WHERE name like ? ORDER BY id", "a%");
        defer it.deinit();
        if (try it.next()) |row1| {
            try expectEqual(1, row1.id);
            try expectEqualStrings("aaa", row1.name);
        } else {
            std.log.err("should return two rows but got none", .{});
        }
        if (try it.next()) |row2| {
            try expectEqual(4, row2.id);
            try expectEqualStrings("aaa2", row2.name);
        } else {
            std.log.err("should return two rows but got only one", .{});
        }
        if (try it.next()) |_| {
            std.log.err("should not return a third row", .{});
        }
    }
}
