const std = @import("std");

pub fn verifyCompilerError(args: struct {
    allocator: std.mem.Allocator,
    test_name: []const u8 = "test",
    test_code: []const u8,
    expected_error: []const u8,
    expected_count: usize = 1,
}) !void {
    const test_file_name = try std.fmt.allocPrint(args.allocator, "src/temp-{s}.zig", .{args.test_name});
    defer args.allocator.free(test_file_name);

    const fh = try std.fs.cwd().createFile(test_file_name, .{});
    var need_close_file = true;
    defer {
        if (need_close_file) {
            fh.close();
            need_close_file = false;
        }
    }
    // defer std.fs.cwd().deleteFile(test_file_name) catch {};

    try fh.writeAll(
        \\ const std = @import("std");
        \\ const mite = @import("mite.zig");
        \\ const allocator = std.testing.allocator;
        \\ fn discard(_: anytype) void {}
        \\
    );
    try fh.writeAll("test \"");
    try fh.writeAll(args.test_name);
    try fh.writeAll("\" {\n");
    try fh.writeAll(args.test_code);
    try fh.writeAll("\n}\n");
    fh.close();
    need_close_file = false;

    const result = try std.process.Child.run(.{
        .allocator = args.allocator,
        .argv = &[_][]const u8{ "zig", "test", test_file_name, "--color", "off" },
    });

    defer args.allocator.free(result.stdout);
    defer args.allocator.free(result.stderr);

    var found_cnt: usize = 0;
    var pos: usize = 0;
    while (std.mem.indexOfPos(u8, result.stderr, pos, args.expected_error)) |found_pos| {
        found_cnt += 1;
        pos += found_pos + args.expected_error.len;
    }

    if (checkIt(found_cnt, args.expected_count)) {
        if (found_cnt == 0) {
            std.log.err("\nexpected compiler error \"{s}\" not found in:\n{s}\n", .{ args.expected_error, result.stderr });
        } else {
            std.log.err("\nexpected compiler error \"{s}\" found {d} time(s) but expected {d} time(s) in:\n---{s}\n", .{ args.expected_error, found_cnt, args.expected_count, result.stderr });
        }
    }
}

fn checkIt(found_cnt: usize, expected_count: usize) bool {
    return found_cnt != expected_count;
}
