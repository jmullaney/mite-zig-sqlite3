const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});

const allocator = std.testing.allocator;

export fn sqlite3_finalize(pStmt: ?*c.sqlite3_stmt) c_int {
    state.last_stmt = pStmt;
    state.last_finalized_stmt = pStmt;
    state.last_rc = c.SQLITE_OK;
    return state.last_rc;
}

export fn sqlite3_prepare_v2(
    db: ?*c.sqlite3,
    zSql: [*c]const u8,
    nByte: c_int,
    ppStmt: [*c]?*c.sqlite3_stmt,
    pzTail: [*c][*c]const u8,
) c_int {
    state.last_db = db;
    state.last_sql = zSql;
    state.last_sql_len = nByte;
    ppStmt.* = state.next_stmt;
    state.last_rc = if (state.next_rc) |next_rc| next_rc else c.SQLITE_OK;
    if (pzTail != null) {
        if (zSql == null or state.last_rc != c.SQLITE_OK) {
            pzTail.* = null;
        } else {
            const sql_len: usize = if (nByte >= 0) @intCast(nByte) else std.mem.len(zSql);
            if (sql_len == 0) {
                pzTail.* = null;
            } else {
                const sql_slice = zSql[0..sql_len];
                const sql_stmt_len = if (std.mem.indexOfScalar(u8, sql_slice, ';')) |pos| pos + 1 else sql_len;
                pzTail.* = zSql + sql_stmt_len;
            }
        }
    }
    return state.last_rc;
}

export fn sqlite3_bind_parameter_count(pStmt: ?*c.sqlite3_stmt) c_int {
    state.last_stmt = pStmt;
    return if (state.next_param_count) |next_param_count| next_param_count else @intCast(state.max_param_count);
}

export fn sqlite3_bind_parameter_name(pStmt: ?*c.sqlite3_stmt, iCol: c_int) [*c]const u8 {
    state.last_stmt = pStmt;
    state.last_iCol = iCol;
    return null;
}

export fn sqlite3_bind_int64(pStmt: ?*c.sqlite3_stmt, iCol: c_int, value: c.sqlite3_int64) c_int {
    state.last_stmt = pStmt;
    state.last_iCol = iCol;
    state.last_int64_value = value;
    const param_count: c_int = if (state.next_param_count) |next_param_count| next_param_count else @intCast(state.max_param_count);
    state.last_rc = if (state.next_rc) |next_rc| next_rc else if (iCol < 1 or iCol > param_count) c.SQLITE_RANGE else c.SQLITE_OK;
    return state.last_rc;
}

export fn sqlite3_bind_double(pStmt: ?*c.sqlite3_stmt, iCol: c_int, value: f64) c_int {
    state.last_stmt = pStmt;
    state.last_iCol = iCol;
    state.last_double_value = value;
    const param_count: c_int = if (state.next_param_count) |next_param_count| next_param_count else @intCast(state.max_param_count);
    state.last_rc = if (state.next_rc) |next_rc| next_rc else if (iCol < 1 or iCol > param_count) c.SQLITE_RANGE else c.SQLITE_OK;
    return state.last_rc;
}

export fn sqlite3_bind_text64(pStmt: ?*c.sqlite3_stmt, iCol: c_int, ptr: [*c]const u8, len: c.sqlite3_uint64, free: ?*const fn (?*anyopaque) callconv(.C) void, encoding: u8) c_int {
    state.last_stmt = pStmt;
    state.last_iCol = iCol;
    state.last_encoding = @intCast(encoding);

    if (ptr != null) {
        const text_len: usize = if (len >= 0) @intCast(len) else std.mem.len(ptr);
        const text_slice = ptr[0..text_len];
        const text_copy = std.fmt.allocPrint(allocator, "{s}", .{text_slice}) catch {
            state.last_rc = c.SQLITE_NOMEM;
            return state.last_rc;
        };

        if (state.last_text_free != null) {
            allocator.free(state.last_text_value);
            state.last_text_free = null;
        }
        state.last_text_value = text_copy;
        state.last_text_free = @intCast(@intFromPtr(free));
    } else {
        state.did_bind_null = true;
    }

    const param_count: c_int = if (state.next_param_count) |next_param_count| next_param_count else @intCast(state.max_param_count);
    state.last_rc = if (state.next_rc) |next_rc| next_rc else if (iCol < 1 or iCol > param_count) c.SQLITE_RANGE else c.SQLITE_OK;
    return state.last_rc;
}

export fn sqlite3_bind_blob64(pStmt: ?*c.sqlite3_stmt, iCol: c_int, opaque_data: ?*const anyopaque, len: c.sqlite3_uint64, free: ?*const fn (?*anyopaque) callconv(.C) void) c_int {
    state.last_stmt = pStmt;
    state.last_iCol = iCol;

    if (opaque_data) |opaque_data_| {
        const data_ptr: [*c]const u8 = @ptrCast(opaque_data_);
        const data_copy = allocator.alloc(u8, len) catch {
            state.last_rc = c.SQLITE_NOMEM;
            return state.last_rc;
        };
        std.mem.copyForwards(u8, data_copy, data_ptr[0..len]);

        if (state.last_blob_free != null) {
            allocator.free(state.last_blob_value);
            state.last_blob_free = null;
        }
        state.last_blob_value = data_copy;
        state.last_blob_free = @intCast(@intFromPtr(free));
    } else {
        state.did_bind_null = true;
    }

    const param_count: c_int = if (state.next_param_count) |next_param_count| next_param_count else @intCast(state.max_param_count);
    state.last_rc = if (state.next_rc) |next_rc| next_rc else if (iCol < 1 or iCol > param_count) c.SQLITE_RANGE else c.SQLITE_OK;
    return state.last_rc;
}

export fn sqlite3_bind_null(pStmt: ?*c.sqlite3_stmt, iCol: c_int) c_int {
    state.last_stmt = pStmt;
    state.last_iCol = iCol;
    state.did_bind_null = true;
    const param_count: c_int = if (state.next_param_count) |next_param_count| next_param_count else @intCast(state.max_param_count);
    state.last_rc = if (state.next_rc) |next_rc| next_rc else if (iCol < 1 or iCol > param_count) c.SQLITE_RANGE else c.SQLITE_OK;
    return state.last_rc;
}

export fn sqlite3_column_int64(pStmt: ?*c.sqlite3_stmt, iCol: c_int) c.sqlite3_int64 {
    state.last_stmt = pStmt;
    state.last_iCol = iCol;
    const col_count: c_int = if (state.next_col_count) |next_col_count| next_col_count else @intCast(state.max_col_count);
    return if (iCol < 0 or iCol >= col_count or iCol >= state.max_col_count) 0 else state.next_int64_value[@intCast(iCol)];
}

export fn sqlite3_column_text(pStmt: ?*c.sqlite3_stmt, iCol: c_int) [*c]const u8 {
    state.last_stmt = pStmt;
    state.last_iCol = iCol;
    return "abc";
}

export fn sqlite3_column_bytes(pStmt: ?*c.sqlite3_stmt, iCol: c_int) c_int {
    state.last_stmt = pStmt;
    state.last_iCol = iCol;
    return 3;
}

export fn sqlite3_column_double(pStmt: ?*c.sqlite3_stmt, iCol: c_int) f64 {
    state.last_stmt = pStmt;
    state.last_iCol = iCol;
    const col_count: c_int = if (state.next_col_count) |next_col_count| next_col_count else @intCast(state.max_col_count);
    return if (iCol < 0 or iCol >= col_count or iCol >= state.max_col_count) 0 else state.next_double_value[@intCast(iCol)];
}

export fn sqlite3_column_type(pStmt: ?*c.sqlite3_stmt, iCol: c_int) c_int {
    state.last_stmt = pStmt;
    state.last_iCol = iCol;
    return c.SQLITE_INTEGER;
}

export fn sqlite3_column_count(pStmt: ?*c.sqlite3_stmt) c_int {
    state.last_stmt = pStmt;
    return 2;
}

export fn sqlite3_column_name(pStmt: ?*c.sqlite3_stmt, iCol: c_int) [*c]const u8 {
    state.last_stmt = pStmt;
    return switch (iCol) {
        0 => "col0",
        1 => "col1",
        else => "colN",
    };
}

export fn sqlite3_step(pStmt: ?*c.sqlite3_stmt) c_int {
    state.last_stmt = pStmt;
    if (state.step_num == state.step_done_num) {
        state.last_rc = if (state.step_done_rc) |step_done_rc| step_done_rc else c.SQLITE_DONE;
    } else {
        state.step_num += 1;
        state.last_rc = if (state.next_rc) |next_rc| next_rc else c.SQLITE_ROW;
    }
    return state.last_rc;
}

fn State(param_cnt: comptime_int, col_cnt: comptime_int) type {
    return struct {
        db1: ?*c.sqlite3 = @ptrCast(&mock_db1),
        db2: ?*c.sqlite3 = @ptrCast(&mock_db2),
        last_db: ?*c.sqlite3 = null,
        last_sql: [*c]const u8 = null,
        last_sql_len: c_int = -999,
        max_param_count: usize = param_cnt,
        max_col_count: usize = col_cnt,
        stmt1: ?*c.sqlite3_stmt = @ptrCast(&mock_stmt1),
        stmt2: ?*c.sqlite3_stmt = @ptrCast(&mock_stmt2),
        last_stmt: ?*c.sqlite3_stmt = null,
        last_finalized_stmt: ?*c.sqlite3_stmt = null,
        last_step_stmt: ?*c.sqlite3_stmt = null,
        step_num: usize = 0,
        step_done_num: usize = 2,
        step_done_rc: ?c_int = null,
        last_rc: c_int = -1,
        last_iCol: c_int = -1,
        last_int64_value: c.sqlite3_int64 = -1,
        last_double_value: f64 = -1.0,
        last_text_value: []const u8 = "",
        last_text_free: ?isize = null,
        last_encoding: i16 = -1,
        last_blob_value: []const u8 = "",
        last_blob_free: ?isize = null,
        did_bind_null: bool = false,
        next_rc: ?c_int = null,
        next_stmt: ?*c.sqlite3_stmt = null,
        next_param_count: ?c_int = null,
        next_col_count: ?c_int = null,
        next_int64_value: [col_cnt]c.sqlite3_int64 = [1]c.sqlite3_int64{-1} ** col_cnt,
        next_double_value: [col_cnt]f64 = [1]f64{-1.0} ** col_cnt,

        pub fn reset(self: *@This()) void {
            self.deinit();
            self.* = @This(){};
        }

        pub fn deinit(self: *@This()) void {
            if (self.last_text_free != null) {
                allocator.free(self.last_text_value);
                self.last_text_free = null;
            }
            if (self.last_blob_free != null) {
                allocator.free(self.last_blob_value);
                self.last_blob_free = null;
            }
        }

        const MockDb = struct { id: usize };
        var mock_db1 = MockDb{ .id = 1 };
        var mock_db2 = MockDb{ .id = 2 };

        const MockStmt = struct { id: usize };
        var mock_stmt1 = MockStmt{ .id = 1 };
        var mock_stmt2 = MockStmt{ .id = 2 };
    };
}

pub var state = State(4, 4){};
