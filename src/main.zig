const std = @import("std");
const mite = @import("mite.zig");
const c = @cImport({
    @cInclude("sqlite3.h");
});

pub fn main() !void {
    const TestRow = struct {
        id: i64,
        name: []const u8,
    };

    var db: ?*c.sqlite3 = null;
    try mite.ok(c.sqlite3_open(":memory:", &db));
    defer _ = c.sqlite3_close(db);

    try mite.run(db, "CREATE TABLE test (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)", .{});
    try mite.run(db, "INSERT INTO test(name) VALUES (?), (?), (?), (?)", .{ "aaa", "bbb2", "ccc", "aaa2" });

    var it = try mite.exec(TestRow, db, "SELECT id, name FROM test WHERE id = ?", 4);
    defer it.deinit();
    while (try it.next()) |row| {
        std.log.info("A row: id = {d}, name = {s}", .{ row.id, row.name });
    }

    try mite.run(db, "CREATE TABLE test2 (id INTEGER PRIMARY KEY AUTOINCREMENT, col1, col2, col3, col4, col5)", .{});

    var stmt: ?*c.sqlite3_stmt = null;
    defer _ = c.sqlite3_finalize(stmt);

    try mite.ok(c.sqlite3_prepare_v2(db, "INSERT INTO test2(col1, col2, col3, col4, col5) VALUES (?, ?, ?, ?, ?)", -1, &stmt, null));
    try mite.ok(c.sqlite3_bind_int64(stmt, 1, 77));
    try mite.ok(c.sqlite3_bind_double(stmt, 2, 6.45));
    const text_value = "";
    try mite.ok(c.sqlite3_bind_text64(stmt, 3, text_value, text_value.len, c.SQLITE_STATIC, c.SQLITE_UTF8));
    const blob_value = [_]u8{};
    try mite.ok(c.sqlite3_bind_blob(stmt, 4, &blob_value, blob_value.len, c.SQLITE_STATIC));
    try mite.ok(c.sqlite3_bind_null(stmt, 5));
    _ = c.sqlite3_step(stmt);
    _ = c.sqlite3_finalize(stmt);
    stmt = null;

    try mite.ok(c.sqlite3_prepare_v2(db, "INSERT INTO test2(col1, col2, col3, col4, col5) VALUES (?, ?, ?, ?, ?)", -1, &stmt, null));
    try mite.ok(c.sqlite3_bind_text64(stmt, 3, null, 0, c.SQLITE_STATIC, c.SQLITE_UTF8));
    try mite.ok(c.sqlite3_bind_blob(stmt, 4, null, 0, c.SQLITE_STATIC));
    _ = c.sqlite3_step(stmt);
    _ = c.sqlite3_finalize(stmt);
    stmt = null;

    try mite.ok(c.sqlite3_prepare_v2(db, "SELECT id, col1, col2, col3, col4, col5 FROM test2 ORDER BY id", -1, &stmt, null));

    _ = c.sqlite3_step(stmt);
    std.log.debug("", .{});
    std.log.debug("row 1:", .{});
    std.log.debug("col1 type: {d}", .{c.sqlite3_column_type(stmt, 1)});
    std.log.debug("col2 type: {d}", .{c.sqlite3_column_type(stmt, 2)});
    std.log.debug("col3 type: {d}", .{c.sqlite3_column_type(stmt, 3)});
    std.log.debug("  len: {d}", .{c.sqlite3_column_bytes(stmt, 3)});
    std.log.debug("col4 type: {d}", .{c.sqlite3_column_type(stmt, 4)});
    std.log.debug("  len: {d}", .{c.sqlite3_column_bytes(stmt, 4)});
    std.log.debug("col5 type: {d}", .{c.sqlite3_column_type(stmt, 5)});

    _ = c.sqlite3_step(stmt);
    std.log.debug("", .{});
    std.log.debug("row 2:", .{});
    std.log.debug("col1 type: {d}", .{c.sqlite3_column_type(stmt, 1)});
    std.log.debug("col2 type: {d}", .{c.sqlite3_column_type(stmt, 2)});
    std.log.debug("col3 type: {d}", .{c.sqlite3_column_type(stmt, 3)});
    std.log.debug("  len: {d}", .{c.sqlite3_column_bytes(stmt, 3)});
    std.log.debug("col4 type: {d}", .{c.sqlite3_column_type(stmt, 4)});
    std.log.debug("  len: {d}", .{c.sqlite3_column_bytes(stmt, 4)});
    std.log.debug("col5 type: {d}", .{c.sqlite3_column_type(stmt, 5)});

    _ = c.sqlite3_finalize(stmt);
    stmt = null;

    const TupDef = struct { i32, []const u8 };
    const z = TupDef{ 1, "sauce" };
    std.log.debug("z = {d}, {s}", z);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var my_list = std.ArrayList(i32).init(allocator);
    defer my_list.deinit();
    try my_list.append(7);
    try my_list.append(65001);

    const ti = @typeInfo(@TypeOf(my_list));
    const decls = ti.@"struct".decls;
    const decls_cnt = decls.len;
    std.log.debug("has {d} decls", .{decls_cnt});
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
