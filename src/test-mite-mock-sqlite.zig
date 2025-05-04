const std = @import("std");
const mite = @import("mite.zig");
const c = @cImport({
    @cInclude("sqlite3.h");
});
const mock = @import("test-mock-sqlite3.zig");
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const allocator = std.testing.allocator;

test "check mock state works as expected" {
    try expectEqual(null, mock.state.last_stmt);
    try expectEqual(-1, mock.state.last_iCol);
    try expectEqual(-1, mock.state.last_int64_value);
    try expectEqual(-1.0, mock.state.last_double_value);
    try expectEqualStrings("", mock.state.last_text_value);
    try expectEqual(null, mock.state.last_text_free);
    try expectEqual(-1, mock.state.last_encoding);
    try expectEqualStrings("", mock.state.last_blob_value);
    try expectEqual(null, mock.state.last_blob_free);
    try expectEqual(-1, mock.state.last_rc);
    try expectEqual(false, mock.state.did_bind_null);

    mock.state.last_stmt = mock.state.stmt1;
    mock.state.last_iCol = 2;
    mock.state.last_int64_value = 44;
    mock.state.last_double_value = 7.56;
    mock.state.last_text_value = try std.fmt.allocPrint(allocator, "-{s}-", .{"apple-sauce"});
    mock.state.last_text_free = -1;
    mock.state.last_encoding = c.SQLITE_UTF8;
    mock.state.last_blob_value = try std.fmt.allocPrint(allocator, "-{s}-", .{"blob-sauce"});
    mock.state.last_blob_free = -1;
    mock.state.last_rc = 7;
    mock.state.did_bind_null = true;

    mock.state.reset();

    try expectEqual(null, mock.state.last_stmt);
    try expectEqual(-1, mock.state.last_iCol);
    try expectEqual(-1, mock.state.last_int64_value);
    try expectEqual(-1.0, mock.state.last_double_value);
    try expectEqualStrings("", mock.state.last_text_value);
    try expectEqual(null, mock.state.last_text_free);
    try expectEqual(-1, mock.state.last_encoding);
    try expectEqualStrings("", mock.state.last_blob_value);
    try expectEqual(null, mock.state.last_blob_free);
    try expectEqual(-1, mock.state.last_rc);
    try expectEqual(false, mock.state.did_bind_null);
}
