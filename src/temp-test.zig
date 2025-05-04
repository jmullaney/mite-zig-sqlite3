 const std = @import("std");
 const mite = @import("mite.zig");
 const allocator = std.testing.allocator;
 fn discard(_: anytype) void {}
test "test" {
 const v1 = [3:0]u16{ 3333, 2222, 1111 };
 _ = try mite.Value.init(v1);
 const v2 = [3:1]u16{ 4444, 3333, 2222 };
 _ = try mite.Value.init(v2);
 const v3 = [3]u4{ 3, 2, 1 };
 _ = try mite.Value.init(v3);
}
