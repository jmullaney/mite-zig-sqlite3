//! **mite**: A sqlite3 "unwrapper":
//!
//! Implements zig idioms for sqlite, without hiding or duplicating sqlite's comprehensive API.
//!
//! --------------------
//!
//! ### • Map sqlite error codes to zig errors
//!
//! fn `ok`(rc: c_int) `SqliteError`!void
//!
//! --------------------
//!
//! ### • Bind arbitrary values, structs, tuples, etc. as parameters to a prepared sqlite statement
//!
//! fn `bindParameters`(stmt: ?*sqlite3_stmt, params: anytype) Error!void
//!
//! fn `allocBindParameters`(allocator: Allocator, stmt: ?*sqlite3_stmt, params: anytype) Error!void
//!
//! fn `bindOneParameter`(stmt: ?*sqlite3_stmt, param_index: c_int, param: anytype) Error!void
//!
//! fn `allocBindOneParameter`(allocator: Allocator, stmt: ?*sqlite3_stmt, param_index: c_int,
//!       param: anytype) Error!void
//!
//! (customizable)
//!
//! --------------------
//!
//! ### • Read values of arbitrary types from a sqlite statement
//!
//! fn `readRow`(RowType: type, stmt: ?*sqlite3_stmt) Error!RowType
//!
//! fn `allocReadRow`(RowType: type, allocator: Allocator, stmt: ?*sqlite3_stmt) Error!RowType
//!
//! fn `readColumn`(T: type, stmt: ?*sqlite3_stmt, col_index: c_int) Error!T
//!
//! fn `allocReadColumn`(T: type, allocator: Allocator, stmt: ?*sqlite3_stmt, col_index: c_int)
//!     Error!T
//!
//! (customizable)
//!
//! --------------------
//!
//! ### • Use zig iterators to step through statement results
//!
//! fn `rowIterator`(RowType: type, stmt: ?*sqlite3_stmt) `RowIterator`(RowType)
//!
//! fn `allocRowIterator`(RowType: type, allocator: Allocator, stmt: ?*sqlite3_stmt)
//!     `AllocRowIterator`(RowType)
//!
//! --------------------
//!
//! ### • Put it all together
//!
//! Execute multiple statements, bind arbitraty parameters, and
//! receive results of an arbitrary type using zig iterators:
//!
//! fn `exec`(RowType: type, db: ?*sqlite3, sql: []const u8, params: anytype) Error!RowIterator(RowType)
//!
//! fn `ptrExec`(RowType: type, db: ?*sqlite3, sql: []const u8, params: anytype)
//!     Error!`RowIterator`(RowType)
//!
//! fn `allocExec`(RowType: type, allocator: Allocator, db: ?*sqlite3, sql: []const u8, params: anytype)
//!     Error!`AllocRowIterator`(RowType)
//!
//! The variants support different memory management options. (There's also `allocExceptArgsExec`())
//!
//! --------------------
//!
//! Additionally, you can:
//!
//! * customize binding by implementing `miteBindParameters`,
//!     `miteAllocBindParameters`, `miteBindOneParameter` or `miteAllocBindOneParameter`.
//!
//! * customize reading by implementing `miteReadRow`,
//!   `miteAllocReadRow`, `miteReadColumn` or `miteAllocReadColumn`.
//!
//! * use convenience functions for common cases:
//!   * `run`() steps through statements to completion when no result is needed
//!   * `get`() and `allocGet`() return the first result from executing one or more statements
//!   * `getOptional`() and `allocGetOptional`() returns the first result if there is one
//!   * similar functions are also available on the row iterators
//!
//! * use the provided zig tagged unions to hold values of the native sqlite3 types:
//!
//! const `Value` = union(enum) {
//!     INTEGER: i64, FLOAT: f64, TEXT: []const u8, BLOB: []const u8, NULL, ... };
//!
//! const `AllocValue` = struct {
//!     allocator: Allocator, value: Value, ... };
//!
//! ...and a few related utilities and helpers.
//!

const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});

/// Converts sqlite3 result codes except SQLITE_OK to a zig error.
pub fn ok(rc: c_int) SqliteError!void {
    if (rc == c.SQLITE_OK) return;
    return rcErr(rc);
}

/// Binds generic parameters to a prepared sqlite3 statement.
///
/// This parameter binder uses sqlite's `SQLITE_STATIC` binding option for text and blobs.
/// This is efficient for large parameter values because no copy is made. However, any memory
/// these point to *must* remain valid for as long as the statement is in use. (See "allocBindParameters"
/// for a variant that makes a copy of such parameters.)
///
/// params can be:
///   * one of the supported single parameter types
///   * a struct, tuple, slice, or array of supported single parameter types
///   * a type implementing `fn miteBindParameters(self: *const @This(), stmt: ?*c.sqlite3_stmt) Error!void`
///   * a pointer or optional of any of the allowed types
///   * a tagged union where the cases are any of the allowed types
///
/// The supported single parameter types are:
///
///   - **ints/comptime ints**
///   - **floats/comptime floats**
///   - **bool** -- true binds as 1, false binds as 0.
///   - **enums** -- binds the tag integer value.
///   - **sentinal-terminated array or pointer to u8** -- binds as UTF-8 text (0 terminator) or blob (any other terminator).
///   - **slice of u8** -- binds as UTF-8 text.
///   - a type implementing `fn miteBindOneParameter(self: *const @This(), stmt: ?*c.sqlite3_stmt, param_index: c_int) Error!void`
///   - **null** -- binds as null.
///   - **pointer or optional** of the supported types
///   - **tagged union** where the cases are of the supported types
///
/// **Parameter Handling**
///     | params type                       | Handling           |
///     |-----------------------------------|--------------------|
///     | one of the single parameter types | binds to parameter index 1 (the first parameter) |
///     | tuple                             | fields bind by index (the first field to parameter 1, the second to parameter 2, etc.) |
///     | struct                            | fields bind by parameter name, with the leading symbol removed. e.g. field "abc" binds to "?abc" |
///     | array, slice                      | each element binds by index (the first element to the first paraameter, the second to parameter 2, etc.) |
///     | null                              | no parameters are bound (for a freshly prepared statement, that means all the parameters are null) |
///     | pointer, optional, tagged union   | handled according to the resolved value. E.g., an optional struct is handled either as null or a struct |
///
/// **Further Details**
///
/// ints: if the value doesn't fit in sqlite's native integer type (i64) it is bound as text in decimal form.
///
/// floats: if the value loses precision when converted to sqlite's native floating point type (f64) it is
/// bound as text, either in decimal form (if it will fit in 24 characters) or using scientific notation.
///
/// Implementations of miteBindParameters and miteBindOneParameter should generally use sqlite's
/// SQLITE_STATIC lifetime option when binding text and blobs to be consistent with the semantics
/// of this function. See `allocBindParameters`() if you want to use SQLITE_TRANSIENT.
pub fn bindParameters(stmt: ?*c.sqlite3_stmt, params: anytype) Error!void {
    if (stmt) |stmt_| try bindParametersPtr(stmt_, &params);
}

/// Binds generic parameters to a prepared sqlite3 statement
///
/// This parameter binder makes an allocated copy of text and blob parameters so that the
/// application doesn't have to ensure the memory for them remains valid for as long as the statement
/// is in use. (See `bindParameters` for a variant that does not make a copy of such parameters.)
///
/// params can be:
///   * one of the supported single parameter types
///   * a struct, tuple, slice, or array of supported single parameter types
///   * a type implementing
///     `fn miteAllocBindParameters(self: *const @This(), allocator: Allocator, stmt: ?*c.sqlite3_stmt) Error!void`
///   * a pointer or optional of any of the allowed types
///   * a tagged union where the cases are any of the allowed types
///
/// The supported single parameter types are:
///
///   - **ints/comptime ints**
///   - **floats/comptime floats**
///   - **bool** -- true binds as 1, false binds as 0.
///   - **enums** -- binds the tag integer value.
///   - **sentinal-terminated array or pointer to u8** -- binds as UTF-8 text (0 terminator) or blob (any other terminator).
///   - **slice of u8** -- binds as UTF-8 text.
///   - a type implementing
///     `fn miteAllocBindOneParameter(self: *const @This(), allocator: Allocator, stmt: ?*c.sqlite3_stmt, param_index: c_int) Error!void`
///   - **null** -- binds as null.
///   - **pointer or optional** of the supported types
///   - **tagged union** where the cases are of the supported types
///
/// **Parameter Handling**
///     | params type                       | Handling           |
///     |-----------------------------------|--------------------|
///     | one of the single parameter types | binds to parameter index 1 (the first parameter) |
///     | tuple                             | fields bind by index (the first field to parameter 1, the second to parameter 2, etc.) |
///     | struct                            | fields bind by parameter name, with the leading symbol removed. e.g. field "abc" binds to "?abc" |
///     | array, slice                      | each element binds by index (the first element to the first paraameter, the second to parameter 2, etc.) |
///     | null                              | no parameters are bound (for a freshly prepared statement, that means all the parameters are null) |
///     | pointer, optional, tagged union   | handled according to the resolved value. E.g., an optional struct is handled either as null or a struct |
///
/// **Further Details**
///
/// ints: if the value doesn't fit in sqlite's native integer type (i64) it is bound as text in decimal form.
///
/// floats: if the value loses precision when converted to sqlite's native floating point type (f64) it is
/// bound as text, either in decimal form (if it will fit in 24 characters) or using scientific notation.
///
/// Implementations of miteAllocBindParameters and miteAllocBindOneParameter should generally either
/// allocate memory for a copy of text and blob values using the provided allocator, or use sqlite's
/// "transient" option, which causes sqlite to make its own internal copy. This is consistent with the
/// semantics of this function. See `bindParameters` if you want to use SQLITE_STATIC.
///
/// There's a complication if you want to use sqlite's "transient" lifetime option: zig does not allow
/// the use of sqlite's built-in SQLITE_TRANSIENT constant. While it's type is a function pointer, it is
/// actually the fixed value -1. Zig does not allow this because -1 is not a valid alignment for a function.
///
/// To workaround this, mite provides `sqlite3_bind_text64_lifetime`() and `sqlite3_bind_blob64_lifetime`().
/// These actually point directly to sqlite's sqlite3_bind_text64() and sqlite3_bind_blob64(), but allow the
/// lifetime to be specified as Sqlite3Lifetime.TRANSIENT (-1) or Sqlite3Lifetime.STATIC (0).
pub fn allocBindParameters(allocator: std.mem.Allocator, stmt: ?*c.sqlite3_stmt, params: anytype) Error!void {
    _ = allocator;
    _ = stmt;
    _ = params;
    @compileError("NYI");
}

/// Reads a generic row from a statement. May be used after sqlite3_step returns SQLITE_ROW.
///
/// This is the non-allocating row reader, which doesn't directly allocate memory.
/// See `allocReadRow`() for a vairant that does, providing some additional flexibility.
///
/// `RowType` must be one of the supported column types, or a struct, tuple, or array
/// composed of them.
///
/// Alternatively, RowType can be a type that implements
/// `fn miteReadRow(stmt: ?*sqlite3_stmt) Error!RowType`.
/// In that case readRow() simply calls through to RowType.miteReadRow.
///
/// The supported column types are:
///   - **ints** and **floats** up to 256 bits
///   - **bool** -- values that sqlite casts to integer 0 are `false`; other values are `true`.
///   - **enums**: read by integer tag
///   - **sentinal-terminated array of u8** -- read as UTF-8 text (0 terminator) or blob (any other terminator).
///   - *lifetime limited* **slice** or **sentinal-terminated pointer** to **u8**: The memory these point to is managed by the sqlite3 statement
///     and remains valid only until the next `sqlite3_step()`, `sqlite3_reset()`, or `sqlite3_finalize()` call on the statement, or,
///     when using `RowIterator`, the iterator is advanced or `deinit()'ed`.
///     or `next()` or `deinit()` call on a row iterator.
///   - any type that implements `fn miteReadColumn(stmt: ?*sqlite3_stmt, col: c_int) Error!@This()`
///     This includes `mite.Value`.
///   - **optional** of any of the types: null is read as null, while non-null values are read as the underlying type.
///
/// #### RowType column handling #####
///   - | RowType                           | Handling           |
///     |-----------------------------------|--------------------|
///     | one of the supported column types | read from column 0 |
///     | tuple                             | fields are read by index (the first field from column 0, the second from column 1, etc.) |
///     | struct                            | fields are read by column name (e.g., a field named "aaa" is read from column "aaa", etc.) |
///     | array                             | each element is read by index (the first element from column 0, the second from column 1, etc.) |
///
/// #### Further Details #####
///
/// ints, floats: Values outside the range or precision of sqlite3's native numeric types can be expressed in the database as text using decimal or scientific notation.
///
/// sentinal-terminated array of `u8`: The sentinal is always written after the last byte read. Fails with error.ValueTooLarge if the database value doesn't fit in the array.
///
/// enums fail with error.InvalidValue if the database value does not correspond to a valid enum tag value.
///
/// struct, tuple: The read fails with error.FieldUndefined if any of the fields of the result are left undefined.
/// Each field must either be read from a column or have a default value.
pub fn readRow(RowType: type, stmt: ?*c.sqlite3_stmt) Error!RowType {
    return try RowReader(RowType).init(stmt).read();
}

/// Reads a generic row from a statement. May be used after sqlite3_step returns SQLITE_ROW.
///
/// This is the allocating row reader, which allocates memory for certain result column types
/// (see below).
///
/// This is more flexible than `readRow()`, but it can be less efficient to copy
/// large results when you don't need to. Also, allocated memory has to be freed after it's
/// no longer used to avoid memory leaks (arena allocators can often make this fairly
/// straightforward, and they are efficient as well).
///
/// `RowType` must be one of the supported column types, or a struct, tuple, array, or
/// std.ArrayList(T) composed of them.
///
/// Alternatively, RowType can be a type that implements
/// `fn miteAllocReadRow(allocator: std.mem.Allocator, stmt: ?*sqlite3_stmt) Error!RowType` or
/// `fn miteReadRow(stmt: ?*sqlite3_stmt) Error!RowType`.
/// In that case allocReadRow() simply calls through to RowType.miteAllocReadRow or
/// RowType.miteReadRow (preferring miteAllocReadRow if both are implemented).
///
/// The supported column types are:
///   - **ints** and **floats** up to 256 bits
///   - **bool** -- values that sqlite casts to integer 0 are `false`; other values are `true`.
///   - **enums**: read by integer tag
///   - **sentinal-terminated array of u8** -- read as UTF-8 text (0 terminator) or blob (any other terminator).
///   - *memory-owning* **slices** and **sentinal-terminated pointers** to **u8**: Memory is allocated for these
///     fields which  must be freed to avoid memory leaks. Unlike the non-allocating readRow, memory for these
///     fields remains valid until explicitly freed.
///   - any type that implements `fn miteAllocReadColumn(allocator: std.mem.Allocator, stmt: ?*sqlite3_stmt, col: c_int) Error!@This()`
///     This includes mite.Value.
///     Memory allocated by miteAllocReadColumn has to be freed after it will no longer be used to avoid memory leaks.
///   - any type that implements `fn miteReadColumn(stmt: ?*sqlite3_stmt, col: c_int) Error!@This()`
///   - **optional** of any of the types: null is read as null, while non-null values are read as the underlying type.
///
/// #### RowType column handling #####
///   - | RowType                           | Handling           |
///     |-----------------------------------|--------------------|
///     | one of the supported column types | read from column 0 |
///     | tuple                             | fields are read by index (the first field from column 0, the second from column 1, etc.) |
///     | struct                            | fields are read by column name (e.g., a field named "aaa" is read from column "aaa", etc.) |
///     | array                             | each element is read by index (the first element from column 0, the second from column 1, etc.) |
///     | std.ArrayList(T)                  | each column is appended, in order, to the array list |
///
/// Additionally, for stucts that have an "allocator" property, the allocator passed into allocReadRow is automatically copied to
/// the "allocator" field. This allows the struct to implement a "deinit" function to free memory allocated for text and blob properties
/// of the row.
///
/// mite provides utility method "mite.freeRow()", which frees memory allocated by "allocReadRow". This allows you to implement
/// implement deinit similar to this: `pub fn deinit(self: *@This()) void { mite.freeRow(@This(), self.allocator); }`
/// To use freeRow() with types that implement miteAllocReadRow or miteAllocReadColumn, the type must also implement "deinit()".
///
/// #### Further Details #####
///
/// When RowType is std.ArrayList, it is constructed using the allocator. The memory it owns should also be freed after it's no
/// longer used (e.g., by calling its deinit or using an arena allocator, etc).
///
/// ints, floats: Values outside the range or precision of sqlite3's native numeric types can be expressed in the database as text using decimal or scientific notation.
///
/// sentinal-terminated array of `u8`: The sentinal is always written after the last byte read. Fails with error.ValueTooLarge if the database value doesn't fit in the array.
///
/// enums fail with error.InvalidValue if the database value does not correspond to a valid enum tag value.
///
/// struct, tuple: The read fails with error.FieldUndefined if any of the fields of the result are left undefined.
/// Each field must either be read from a column or have a default value.
///
/// If a column type implements both miteAllocReadColumn and miteReadColumn, miteAllocReadColumn is used.
///
/// If a RowType implements both miteAllocReadRow and miteReadRow, miteAllocReadRow is used.
///
/// When implementing miteReadRow, miteReadColumn, miteAllocReadRow, and miteAllocReadColumn, be
/// careful when using sqlite functions that return pointers to memory managed by sqlite,
/// like sqlite3_column_text, sqlite3_column_blob, etc.
///
/// This memory remains valid only for a limited time so pointers to the memory should not be returned
/// in the result of allocReadRow. If you need to return such values, implement miteAllocReadRow or
/// miteAllocReadColumn to allocate the memory needed for the value using the provided allocator, and copy the
/// value to the allocated memory. These receive the same allocator passed into allocReadRow.
pub fn allocReadRow(RowType: type, allocator: std.mem.Allocator, stmt: ?*c.sqlite3_stmt) Error!RowType {
    return try AllocRowReader(RowType).init(allocator, stmt).read();
}

/// Implements an idiomatic zig iterator to read multiple rows from a prepared statement.
/// This can be slightly more efficient than readRow() when reading multiple rows.
///
/// This is based on the "static" `readRow`(), which doesn't directly allocate memory.
///
/// See `readRow`() for information on the handling of RowType.
///
/// Be careful of **slices** and **sentinal-terminated pointers** to **u8** values.
/// These remain valid only until the iterator is next advanced or `deinit()'ed`, or
/// `sqlte3_step`, `sqlite3_finalize`, or `sqlite3_reset` is called on the underlying statement.
///
/// (`allocRowIterator`() does not have this limitation.)
pub fn rowIterator(RowType: type, stmt: ?*c.sqlite3_stmt) RowIterator(RowType) {
    return .{
        .row_reader = RowReader(RowType).init(stmt),
    };
}

/// Implements an idiomatic zig iterator to read multiple rows from a prepared statement.
/// This can be slightly more efficient than readRow() when reading multiple rows.
///
/// This is based on `allocReadRow`(), which allocates memory for text and blob
/// values that point to memory. This means result values can outlive the iterator, but
/// the caller takes responsibility to free the memory once the values are no longer in use.
///
/// One strategy is to use an areana allocator so that you don't have to free each
/// memory allocation separately. Alternatively, you can use a struct that has an
/// `allocator` property and implements deinit(). See `allocReadRow()` and the guide
/// for more information on this.
///
/// See `allocReadRow`() for information on the handling of RowType.
pub fn allocRowIterator(RowType: type, allocator: std.mem.Allocator, stmt: ?*c.sqlite3_stmt) AllocRowIterator(RowType) {
    return .{
        .row_reader = AllocRowReader(RowType).init(allocator, stmt),
    };
}

/// The errors mite can return
pub const Error = error{
    /// Error returned from `get()` when the query has no result.
    NoResult,
    /// Error returned when a query leaves a field of the result row undefined. All fields must have a corresponding column in the query or have a default value.
    UndefinedField,
    /// Error returned when binding a numeric parameter or returning a numeric result but the value is too large; integers and floats up to 256 bits are supported.
    NumberTooLarge,
    /// TODO: remove this and fix the places it's used; there should be a compile error when a non-numeric type is used where a numeric type is expected; std.fmt.ParseIntError and std.fmt.ParseFloatError should provide better runtime errors
    NotANumber,
} || SqliteError || std.mem.Allocator.Error;
// || std.fmt.ParseIntError || std.fmt.ParseFloatError || std.fmt.BufPrintError?

/// Returns a typed row iterator that executes sql statements.
/// Parameters are bound to the first statement.
///
/// This is the "static" exec() variant, which has the following advantages and limitations:
///
/// - Efficienct: does not copy `sql` or `params`.
/// - Any pointers or slices in `params` must remain valid until the iterator returns null or an error, or is deinit()'ed
/// - `sql` must also remain valid if it contains multiple statements.
///
/// `RowType` can be any of the types supported by `readRow`() *except* for *lifetime limited* slices and
/// sentinal-terminated pointers to u8. (For those, use `allocExec`() or `ptrExec`().)
pub fn exec(RowType: type, db: ?*c.sqlite3, sql: []const u8, params: anytype) Error!RowIterator(RowType) {

    // TODO: comptime check of RowType for the types ptrExec can handle but exec cannot
    // (slices and sentinal-terminated pointers to `u8`)

    return ptrExec(RowType, db, sql, params);
}

/// This variant of exec imposes the same limitations on `sql` and `params` as `exec`().
/// It supports the same RowTypes, except that it also allows slices and sentinal-terminated
/// pointers to `u8`.
///
/// However, these values remain valid only until the iterator is next advanced or deinit()'ed, or
/// `sqlte3_step`, `sqlite3_finalize`, or `sqlite3_reset` is called on the underlying statement.
pub fn ptrExec(RowType: type, db: ?*c.sqlite3, sql: []const u8, params: anytype) Error!RowIterator(RowType) {
    var statements = try PreparedStatements.init(db, sql);
    errdefer statements.deinit();

    const stmt = try statements.next();
    errdefer _ = c.sqlite3_finalize(stmt);

    try bindParameters(stmt, params);

    return .{
        .row_reader = RowReader(RowType).init(stmt),
        .remainder = statements,
    };
}

/// Executes one or more SQL statements without returning a result.
pub fn run(db: ?*c.sqlite3, sql: []const u8, params: anytype) Error!void {
    var it = try exec(struct {}, db, sql, &params);
    return it.run();
}

/// Returns the first result from executing SQL statements, if there is one.
///
/// This uses `exec`() and has the same limitations on the result type. Specifically,
/// the result cannot include slices and sentinal-terminated pointers to u8.
/// (See `allocGetOptional`() for a variant that allows these.)
///
/// Note: the SQL is executed only as much as needed to get the first result.
/// E.g., if `sql` contains three statements and the first one returns no results
/// and the second one would return 10 results if executed fully, the first statement
/// would be executed fully, only the first step of the second statement would be executed,
/// and the third statement wouldn't be executed at all.
pub fn getOptional(T: type, db: ?*c.sqlite3, sql: []const u8, params: anytype) Error!?T {
    // TODO: reject T that has []u8 or [*:0] since those will be invalid
    var it = try exec(T, db, sql, &params);
    return it.getOptional();
}

/// Returns the first result from executing SQL statements, or error.NoResult if
/// there is none.
///
/// This uses `exec`() and has the same limitations on the result type. Specifically,
/// the result cannot include slices and sentinal-terminated pointers to u8.
/// (See `allocGet`() for a variant that allows these.)
///
/// Note: the SQL is executed only as much as needed to get the first result.
/// E.g., if `sql` contains three statements and the first one returns no results
/// and the second one would return 10 results if executed fully, the first statement
/// would be executed fully, only the first step of the second statement would be executed,
/// and the third statement wouldn't be executed at all.
pub fn get(T: type, db: ?*c.sqlite3, sql: []const u8, params: anytype) Error!T {
    // TODO: reject T that has []u8 or [*:0] since those will be invalid
    var it = try exec(T, db, sql, &params);
    return it.get();
}

/// Returns a typed row iterator that executes sql statements.
/// Parameters are bound to the first statement.
/// Memory needed for the result is allocated using the provided allocator.
///
/// This is the allocating version of `exec`():
///
/// - copies memory referenced by `sql` and `params` so that the caller does not need to ensure
///   these remain valid after allocExec returns.
///
/// `RowType` can be any of the types supported by `allocReadRow`().
///
/// Memory is allocated for results that point to text and blobs. This means results can outlive
/// the iterator, but the caller is responsible to free the memory when it's no longer in use.
///
/// There are two common strategies:
///
///   1. a RowType is used that has an allocator property and implements deinit(). deinit() is
///      called on each row when it is no longer in use.
///   2. An arena allocator is used. The memory used by all the results is freed at once when
///      the arena allocator is deinit'ed.
pub fn allocExec(RowType: type, allocator: std.mem.Allocator, db: ?*c.sqlite3, sql: []const u8, params: anytype) Error!AllocRowIterator(RowType) {
    var exec_args_mem = std.heap.ArenaAllocator.init(allocator);
    errdefer exec_args_mem.deinit();

    var statements = try PreparedStatements.init(db, sql);
    errdefer statements.deinit();

    const stmt = try statements.next();
    errdefer _ = c.sqlite3_finalize(stmt);

    if (statements.tail.len != 0) {
        statements.tail = try exec_args_mem.allocator().dupe(u8, statements.tail);
    }

    try allocBindParameters(exec_args_mem.allocator(), stmt, params);

    return .{
        .row_reader = AllocRowReader(RowType).init(allocator, stmt),
        .remainder = statements,
        .exec_args_mem = exec_args_mem,
    };
}

/// Specialized version of `allocExec`() that uses the allocator for result rows, but not sql or params.
/// This means any pointers in params must remain valid while the iterator is in-use, and sql must
/// remain valid if it contains multiple statements.
///
/// RowType and results are handled as documented for `allocExec`().
///
/// (This is a minor optimization over `allocExec` in most cases, so this should probably only be used
/// when you have specific reasons to think it will be helpful.)
pub fn allocExceptArgsExec(RowType: type, allocator: std.mem.Allocator, db: ?*c.sqlite3, sql: []const u8, params: anytype) Error!AllocRowIterator(RowType) {
    var statements = try PreparedStatements.init(db, sql);
    errdefer statements.deinit();

    const stmt = try statements.next();
    errdefer _ = c.sqlite3_finalize(stmt);

    try bindParameters(stmt, params);

    return .{
        .row_reader = AllocRowReader(RowType).init(allocator, stmt),
        .remainder = statements,
    };
}

/// Returns the first result from executing SQL statements, if there is one.
///
/// T is handled the same a `allocExec`'s RowType.
///
/// Memory is allocated using the provided allocator for results that point to text and blobs.
/// The caller is responsible for freeing this memory.
///
/// There are two common strategies:
///
///   1. a type is used that has an allocator property and implements deinit(). deinit() is
///      called on the reuslt when it is no longer in use.
///   2. An arena allocator is used. The memory used is freed when the arena allocator is deinit'ed.
///
/// Note: the SQL is executed only as much as needed to get the first result.
/// E.g., if `sql` contains three statements and the first one returns no results
/// and the second one would return 10 results if executed fully, the first statement
/// would be executed fully, only the first step of the second statement would be executed,
/// and the third statement wouldn't be executed at all.
pub fn allocGetOptional(T: type, allocator: std.mem.Allocator, db: ?*c.sqlite3, sql: []const u8, params: anytype) Error!?T {
    var it = try allocExceptArgsExec(T, allocator, db, sql, &params);
    return it.getOptional();
}

/// Returns the first result from executing SQL statements, or error.NoResult if there is none.
///
/// T is handled the same a `allocExec`'s RowType.
///
/// Memory is allocated using the provided allocator for results that point to text and blobs.
/// The caller is responsible for freeing this memory.
///
/// There are two common strategies:
///
///   1. a type is used that has an allocator property and implements deinit(). deinit() is
///      called on the reuslt when it is no longer in use.
///   2. An arena allocator is used. The memory used is freed when the arena allocator is deinit'ed.
///
/// Note: the SQL is executed only as much as needed to get the first result.
/// E.g., if `sql` contains three statements and the first one returns no results
/// and the second one would return 10 results if executed fully, the first statement
/// would be executed fully, only the first step of the second statement would be executed,
/// and the third statement wouldn't be executed at all.
pub fn allocGet(T: type, allocator: std.mem.Allocator, db: ?*c.sqlite3, sql: []const u8, params: anytype) Error!T {
    var it = try allocExceptArgsExec(T, allocator, db, sql, &params);
    return it.get();
}

/// Binds a generic parameter to a prepared sqlite statement at the parameter index specified.
///
/// See `bindParameters`() for details on the types supported for param and the handling of
/// parameter values.
pub fn bindOneParameter(stmt: ?*c.sqlite3_stmt, param_index: c_int, param: anytype) Error!void {
    return bindOneParameterPtr(stmt, param_index, &param);
}

/// Binds a generic parameter to a prepared sqlite statement at the parameter index specified.
///
/// See `allocBindParameters`() for details on the types supported for param and the handling of
/// parameter values.
pub fn allocBindOneParameter(allocator: std.mem.Allocator, stmt: ?*c.sqlite3_stmt, param_index: c_int, param: anytype) Error!void {
    _ = allocator;
    _ = stmt;
    _ = param_index;
    _ = param;
    @compileError("NYI");
    // return bindOneParameterPtr(stmt, param_index, &param);
}

/// Returns true when the type is a single parameter type supported by `bindOneParameter`,
/// and `bindParameters`.
///
/// (This is useful for generic code. It can be used at comptime to determine if bindOneParameter
/// or bindParameters can be called for a given type without a compiler error.)
pub fn isOneParameterType(T: type) bool {
    return comptime hasMiteBindOneParameterFn(T) or Value.isDirectlyRepresentableType(T);
}

/// Returns true when the type is a single parameter type supported by `allocBindOneParameter`,
/// and `allocBindParameters`.
///
/// (This is useful for generic code. It can be used at comptime to determine if allocBindOneParameter
/// or allocBindParameters can be called for a given type without a compiler error.)
pub fn isOneAllocParameterType(T: type) bool {
    return comptime hasMiteBindOneParameterFn(T) or AllocValue.isDirectlyRepresentableType(T);
}

pub fn funcWithCompilerError() void {
    @compileError("compiler error!");
}

/// A tagged union that hold sqlite's native values.
/// Can be used for binding parameters and reading values.
/// When reading, the value returned is of the type the column
/// has in the database, without conversion or cast. This value
/// does *not* own the memory pointed to by TEXT and BLOB.
pub const Value = union(enum) {
    INTEGER: c.sqlite3_int64,
    FLOAT: f64,
    TEXT: []const u8,
    BLOB: []const u8,
    NULL,

    /// Initializes a `Value` instance from a generic value.
    ///
    /// A compiler error occurs if used with a type it cannot handle.
    /// Returns error.NumberTooLarge if an integer or float value is
    /// outside the range of i64 or f64 (sqlite's native number formats).
    pub fn init(param: anytype) error{NumberTooLarge}!Value {
        if (@TypeOf(param) == Value) {
            return param;
        }

        const type_info = comptime @typeInfo(@TypeOf(param));
        switch (type_info) {
            .bool => {
                return Value{ .INTEGER = if (param) 1 else 0 };
            },
            .int => |int_info| {
                if (int_info.bits < 64 or (int_info.bits == 64 and int_info.signedness == .signed) or (param >= std.math.minInt(i64) and param <= std.math.maxInt(i64))) {
                    return Value{ .INTEGER = @intCast(param) };
                } else {
                    return Error.NumberTooLarge;
                }
            },
            .comptime_int => {
                if (param >= std.math.minInt(i64) and param <= std.math.maxInt(i64)) {
                    return Value{ .INTEGER = @intCast(param) };
                } else {
                    return Error.NumberTooLarge;
                }
            },
            .float => |float_info| {
                if (float_info.bits <= 64 or @as(@TypeOf(param), @floatCast(@as(f64, @floatCast(param)))) == param) {
                    return Value{ .FLOAT = @floatCast(param) };
                } else {
                    return Error.NumberTooLarge;
                }
            },
            .comptime_float => {
                if (@as(f128, @floatCast(@as(f64, param))) == @as(f128, param)) {
                    return Value{ .FLOAT = @floatCast(param) };
                } else {
                    return Error.NumberTooLarge;
                }
            },
            .@"enum" => {
                return init(@intFromEnum(param));
            },
            .null => {
                return Value.NULL;
            },
            .pointer => |pointer_info| {
                switch (pointer_info.size) {
                    .slice => {
                        if (pointer_info.child == u8) {
                            // []u8 treated as string
                            return Value{ .TEXT = param };
                        } else {
                            @compileError("slice of non-u8 is not supported (type is " ++ @typeName(@TypeOf(param)) ++ ")");
                        }
                    },
                    .one => {
                        const child_type_info = @typeInfo(pointer_info.child);
                        if (child_type_info == .array and child_type_info.array.child == u8) {
                            return Value{ .TEXT = param[0..] };
                        } else {
                            return init(param.*);
                        }
                    },
                    else => {
                        @compileError("Many and C pointers not supported; the number of items pointed to is unknown");
                    },
                }
            },
            .optional => {
                if (param) |unwrapped_param| {
                    return init(unwrapped_param);
                } else {
                    return Value.NULL;
                }
            },
            .@"union" => {
                if (type_info.@"union".tag_type) |tag_type| {
                    const active_tag_value = @intFromEnum(@as(tag_type, param));
                    inline for (@typeInfo(tag_type).@"enum".fields) |tag_field| {
                        if (active_tag_value == tag_field.value) {
                            const active_value = @field(param, tag_field.name);
                            return init(active_value);
                        }
                    }
                    @panic("unable to resolve tagged union value");
                } else {
                    @compileError("cannot bind untagged union");
                }
            },
            .array => {
                @compileError("array type not supported binding one parameter (type is " ++ @typeName(@TypeOf(param)) ++ "); you can pass a pointer to sentinal-terminared array, though the value must not outlive the array");
            },
            .@"struct" => {
                @compileError("struct type not supported binding one parameter (type is " ++ @typeName(@TypeOf(param)) ++ "); you can implement miteBindOneParmeter() to allow binding a struct as one parameter");
            },
            else => {
                @compileError("unsupported type " ++ @typeName(@TypeOf(param)));
            },
        }
    }

    /// Binds the value using the appropriate sqlite3_bind_NNN() function, based on its type.
    pub fn miteBindOneParameter(self: *const @This(), stmt: ?*c.sqlite3_stmt, param_index: c_int) SqliteError!void {
        const rc = switch (self.*) {
            .INTEGER => |v| c.sqlite3_bind_int64(stmt, param_index, v),
            .FLOAT => |v| c.sqlite3_bind_double(stmt, param_index, v),
            .TEXT => |v| sqlite3_bind_text64_lifetime(stmt, param_index, v.ptr, @intCast(v.len), .TRANSIENT, c.SQLITE_UTF8),
            .BLOB => |v| sqlite3_bind_blob64_lifetime(stmt, param_index, v.ptr, @intCast(v.len), .TRANSIENT),
            .NULL => c.sqlite3_bind_null(stmt, param_index),
        };
        return ok(rc);
    }

    /// Indicates whether the type can be directly represented as a Value.
    ///
    /// (This is useful for generic code. It can be used at comptime to determine if a type can be used
    /// with `Value` without compiler errors.
    pub fn isDirectlyRepresentableType(T: type) bool {
        if (T == Value) return true;
        const type_info = @typeInfo(T);
        switch (type_info) {
            .bool, .int, .comptime_int, .float, .comptime_float, .@"enum", .null => return true,
            .pointer => |pointer_info| {
                switch (pointer_info.size) {
                    .slice => {
                        return pointer_info.child == u8;
                    },
                    .one => {
                        const child_type_info = @typeInfo(pointer_info.child);
                        if (child_type_info == .array and child_type_info.array.child == u8) {
                            return true;
                        } else {
                            return isDirectlyRepresentableType(pointer_info.child);
                        }
                    },
                    else => {
                        return false;
                    },
                }
            },
            .optional => {
                return isDirectlyRepresentableType(type_info.Optional.child);
            },
            .@"union" => {
                if (type_info.@"union".tag_type != null) {
                    inline for (type_info.@"union".fields) |union_field| {
                        if (!isDirectlyRepresentableType(union_field.type)) return false;
                    }
                    return true;
                } else {
                    return false;
                }
            },
            .array, .@"struct" => return false,
            else => false,
        }
    }
};

/// A struct that hold a Value containing a native sqlite value
/// and an allocator that owns any memory allocated for the value.
/// Memory is allocated for .TEXT and .BLOB values but not for
/// .INTEGER, .FLOAT, and .NULL values.
/// Use its deinit() to free this memory.
pub const AllocValue = struct {
    allocator: std.mem.Allocator,
    value: Value,

    /// Initializes an `AllocValue` instance from a generic value.
    ///
    /// A compiler error occurs if used with a type it cannot handle.
    ///
    /// Converts integer and floats that are outside the range/preceision
    /// of i64 or f64 (sqlite's native number formats) to text, holding
    /// a decimal or scientific notation representation of the number.
    pub fn init(allocator: std.mem.Allocator, param: anytype) error{OutOfMemory}!AllocValue {
        if (Value.init(param)) |value_| {
            const value = switch (value_) {
                .TEXT => |text| Value{ .TEXT = try allocator.dupe(u8, text) },
                .BLOB => |blob| Value{ .BLOB = try allocator.dupe(u8, blob) },
                else => value_,
            };
            return .{
                .allocator = allocator,
                .value = value,
            };
        } else |err| {
            switch (err) {
                error.NumberTooLarge => {
                    var textSlice: []const u8 = undefined;
                    switch (@typeInfo(@TypeOf(param))) {
                        .float, .comptime_float => {
                            var buf: [24]u8 = undefined;
                            var fba = std.heap.FixedBufferAllocator.init(&buf);
                            if (allocPrintNumberValue(fba.allocator(), "{d}", param)) |decimalText| {
                                textSlice = try allocator.dupe(u8, decimalText);
                            } else |_| {
                                textSlice = allocPrintNumberValue(allocator, "{e}", param) catch {
                                    return Error.OutOfMemory;
                                };
                            }
                        },
                        else => {
                            textSlice = allocPrintNumberValue(allocator, "{d}", param) catch {
                                return Error.OutOfMemory;
                            };
                        },
                    }
                    return .{ .allocator = allocator, .value = .{ .TEXT = textSlice } };
                },
            }
        }
    }

    pub fn deinit(self: @This()) void {
        switch (self.value) {
            .TEXT => |text| self.allocator.free(text),
            .BLOB => |blob| self.allocator.free(blob),
        }
    }

    /// Binds the value using the appropriate sqlite3_bind_NNN() function, based on its type.
    pub fn miteBindOneParameter(self: *const @This(), stmt: ?*c.sqlite3_stmt, param_index: c_int) SqliteError!void {
        return self.value.miteBindOneParameter(stmt, param_index);
    }

    /// Indicates can be directly represented as a Value.
    ///
    /// (This is useful for generic code. It can be used at comptime to determine if a type can be used
    /// with `Value` without compiler errors.
    pub fn isDirectlyRepresentableType(T: type) bool {
        return comptime Value.isDirectlyRepresentableType(T);
    }
};

// These work around an issue with zig and sqlite's "lifetime" parameter for sqlite3_bind_text64 and sqlite3_bind_blob64.
// That parameter is a pointer to a function, but it also accepts two special values that aren't really function pointers:
// 0 for "static" lifetime and -1 for "transient" lifetime. Zig wants to enforce alignment of function pointers so it
// doesn't allow -1. These provide alternate signatures for the sqlite functions, where the lifetime parameter is presented
// as an isize-based enum. This gets zig to allow -1 to be passed. Since isize is the same size as the function pointer,
// these match the ABI of the original functions and can point directly to the original.

/// Calls through to sqlite's `sqlite3_bind_text64`, but allows the lifetime to be specified as .TRANSIENT or .STATIC.
/// This works around the issue that zig doesn't allow sqlite's special SQLITE_TRANSIENT value to be used.
pub const sqlite3_bind_text64_lifetime: *const fn (?*c.sqlite3_stmt, c_int, [*c]const u8, c.sqlite3_uint64, Sqlite3Lifetime, u8) callconv(.c) c_int = @ptrCast(&c.sqlite3_bind_text64);

/// Calls through to sqlite's `sqlite3_bind_blob64`, but allows the lifetime to be specified as .TRANSIENT or .STATIC.
/// This works around the issue that zig doesn't allow sqlite's special SQLITE_TRANSIENT value to be used.
pub const sqlite3_bind_blob64_lifetime: *const fn (?*c.sqlite3_stmt, c_int, ?*const anyopaque, c.sqlite3_uint64, Sqlite3Lifetime) callconv(.c) c_int = @ptrCast(&c.sqlite3_bind_blob64);

/// Lifetime values for `sqlite3_bind_text64_lifetime` and `sqlite3_bind_blob64_lifetime`.
pub const Sqlite3Lifetime = enum(isize) {
    /// corresponds to SQLITE3_TRANSIENT
    TRANSIENT = -1,
    /// corresponds to SQLITE3_STATIC
    STATIC = 0,
};

fn allocPrintNumberValue(allocator: std.mem.Allocator, comptime fmt: []const u8, param: anytype) (std.fmt.AllocPrintError || error{NotANumber})![]u8 {
    const type_info = comptime @typeInfo(@TypeOf(param));
    switch (type_info) {
        .int, .comptime_int, .float, .comptime_float => {
            return std.fmt.allocPrint(allocator, fmt, .{param});
        },
        .pointer => |pointer_info| {
            if (pointer_info.size == .one) {
                return allocPrintNumberValue(allocator, fmt, param.*);
            }
        },
        .@"enum" => {
            return allocPrintNumberValue(allocator, fmt, @intFromEnum(param));
        },
        .optional => {
            if (param) |unwrapped_param| {
                return allocPrintNumberValue(allocator, fmt, unwrapped_param);
            }
        },
        .@"union" => {
            if (type_info.@"union".tag_type) |tag_type| {
                const active_tag_value = @intFromEnum(@as(tag_type, param));
                inline for (@typeInfo(tag_type).@"enum".fields) |tag_field| {
                    if (active_tag_value == tag_field.value) {
                        const active_value = @field(param, tag_field.name);
                        return allocPrintNumberValue(allocator, fmt, active_value);
                    }
                }
            }
        },
        else => {},
    }
    return Error.NotANumber;
}

/// Reads a generic column value from a statement. May be used after sqlite3_step returns SQLITE_ROW.
///
/// See `readRow`() for details on the types supported for T and the handling of results.
pub fn readColumn(comptime T: type, stmt: ?*c.sqlite3_stmt, col_index: c_int) Error!T {
    if (comptime std.meta.hasFn(T, "miteReadColumn")) {
        return T.miteReadColumn(stmt, col_index);
    }

    const type_info = comptime @typeInfo(T);
    switch (type_info) {
        .bool => {
            const value = c.sqlite3_column_int64(stmt, col_index);
            return value != 0;
        },
        .int => |int_info| {
            if (int_info.bits < 64 or (int_info.bits == 64 and int_info.signedness == .signed) or c.sqlite3_column_type(stmt, col_index) == c.SQLITE_INTEGER) {
                const value = c.sqlite3_column_int64(stmt, col_index);
                return @intCast(value);
            } else {
                const value_ptr = c.sqlite3_column_text(stmt, col_index);
                const value_len = c.sqlite3_column_bytes(stmt, col_index);
                const value_slice = value_ptr[0..@intCast(value_len)];
                const value = try std.fmt.parseInt(T, value_slice, 10);
                return value;
            }
        },
        .float => |float_info| {
            if (float_info.bits <= 64 or c.sqlite3_column_type(stmt, col_index) == c.SQLITE_FLOAT) {
                const value = c.sqlite3_column_double(stmt, col_index);
                return @floatCast(value);
            } else {
                const value_ptr = c.sqlite3_column_text(stmt, col_index);
                const value_len = c.sqlite3_column_bytes(stmt, col_index);
                const value_slice = value_ptr[0..@intCast(value_len)];
                const value = try std.fmt.parseFloat(T, value_slice);
                return value;
            }
        },
        .pointer => |pointer_info| {
            if (pointer_info.child == u8) {
                switch (pointer_info.size) {
                    .slice => {
                        const value_ptr = c.sqlite3_column_text(stmt, col_index);
                        const value_len = c.sqlite3_column_bytes(stmt, col_index);
                        const value_slice = value_ptr[0..@intCast(value_len)];
                        return value_slice;
                    },
                    .many => {
                        return c.sqlite3_column_text(stmt, col_index);
                    },
                    .c => {
                        return c.sqlite3_column_text(stmt, col_index);
                    },
                    else => {
                        // C and Many of u8 could be directly supported
                        @compileError("unsupported pointer type " ++ @typeName(T));
                    },
                }
            } else {
                @compileError("unsupported pointer type " ++ @typeName(T));
            }
        },
        .@"enum" => |enum_info| {
            const tag_value = try readColumn(enum_info.tag_type, stmt, col_index);
            return @enumFromInt(tag_value);
        },
        .optional => {
            if (c.sqlite3_column_type() == c.SQLITE_NULL) {
                return null;
            } else {
                return readColumn(type_info.Optional.child, stmt, col_index);
            }
        },
        .null => {
            return null;
        },
        .@"struct" => {
            @compileError("unsupported struct type " ++ @typeName(T));
        },
        else => {
            @compileError("unsupported type " ++ @typeName(T));
        },
    }
}

fn bindOneParameterPtr(stmt: ?*c.sqlite3_stmt, param_index: c_int, param_ptr: anytype) Error!void {
    const param_ptr_type_info = @typeInfo(@TypeOf(param_ptr));
    if (param_ptr_type_info != .pointer or param_ptr_type_info.pointer.size != .one) {
        @compileError("expected pointer to one but got " ++ @typeName(@TypeOf(param_ptr)));
    }

    if (comptime hasMiteBindOneParameterFn(param_ptr_type_info.pointer.child)) {
        return callParamPtrMiteBindOneParameterFn(param_ptr, stmt, param_index);
    }

    if (Value.init(param_ptr)) |value| {
        return value.miteBindOneParameter(stmt, param_index);
    } else |err| {
        switch (err) {
            error.NumberTooLarge => {
                var large_number_buf: [96]u8 = undefined;
                var fba = std.heap.FixedBufferAllocator.init(&large_number_buf);
                const allocValue = try AllocValue.init(fba.allocator(), param_ptr);
                return allocValue.value.miteBindOneParameter(stmt, param_index);
            },
        }
    }
}

fn hasMiteBindOneParameterFn(T: type) bool {
    if (comptime std.meta.hasFn(T, "miteBindOneParameter")) {
        return true;
    }
    return comptime switch (@typeInfo(T)) {
        .pointer => |pointer_info| pointer_info.size == .one and hasMiteBindOneParameterFn(pointer_info.child),
        .optional => |optional_info| hasMiteBindOneParameterFn(optional_info.child),
        else => false,
    };
}

fn callParamPtrMiteBindOneParameterFn(param_ptr: anytype, stmt: ?*c.sqlite3_stmt, param_index: c_int) Error!void {
    const param_ptr_type_info = @typeInfo(@TypeOf(param_ptr));
    if (param_ptr_type_info != .pointer or param_ptr_type_info.pointer.size != .one) {
        @compileError("param_ptr must be a pointer to one parameter");
    }

    const TParam = param_ptr_type_info.pointer.child;
    if (comptime std.meta.hasFn(TParam, "miteBindOneParameter")) {
        return TParam.miteBindOneParameter(param_ptr, stmt, param_index);
    }

    switch (@typeInfo(TParam)) {
        .pointer => {
            return callParamPtrMiteBindOneParameterFn(param_ptr.*, stmt, param_index);
        },
        .optional => {
            if (param_ptr.*) |unwrapped_param| {
                return callParamPtrMiteBindOneParameterFn(&unwrapped_param, stmt, param_index);
            } else {
                // bind null for null optional
                return ok(c.sqlite3_bind_null(stmt, param_index));
            }
        },
        else => {
            @compileError("type " ++ @typeName(TParam) ++ " does not have a miteBindOneParameter() function to call");
        },
    }
}

fn bindParametersPtr(stmt: *c.sqlite3_stmt, params_ptr: anytype) Error!void {
    const params_ptr_type_info = @typeInfo(@TypeOf(params_ptr));
    if (params_ptr_type_info != .pointer) {
        @compileError("expected pointer to one or slice but got " ++ @typeName(@TypeOf(params_ptr)));
    }

    const TParams = params_ptr_type_info.pointer.child;
    const params_type_info = @typeInfo(TParams);

    const param_count: usize = @intCast(c.sqlite3_bind_parameter_count(stmt));
    if (param_count == 0) return;

    if (comptime isOneParameterType(TParams)) {
        return bindOneParameterPtr(stmt, 1, params_ptr);
    }

    switch (params_ptr_type_info.pointer.size) {
        .one => {
            switch (params_type_info) {
                .array => {
                    // bind each by array index
                    for (params_ptr, 0..) |*param_ptr, index| {
                        if (index >= param_count) break;
                        try bindOneParameterPtr(stmt, @intCast(index + 1), param_ptr);
                    }
                },
                .optional => {
                    if (params_ptr.*) |params| {
                        // bind recursively
                        return bindParametersPtr(stmt, &params);
                    } else {
                        // do nothing? or bind nulls for all params?
                    }
                },
                .pointer => {
                    // bind recursively
                    return bindParametersPtr(stmt, params_ptr.*);
                },
                .@"struct" => |struct_info| {
                    const params_fields = comptime params_type_info.@"struct".fields;
                    if (struct_info.is_tuple) {
                        // bind each field by index
                        inline for (params_fields, 0..) |field, index| {
                            if (index >= param_count) break;
                            const param = @field(params_ptr.*, field.name);
                            try bindOneParameterPtr(stmt, @intCast(index + 1), &param);
                        }
                    } else {
                        // bind each field by name
                        for (0..param_count) |index| {
                            const param_index: c_int = @intCast(index + 1);
                            if (c.sqlite3_bind_parameter_name(stmt, param_index)) |col_namez| {
                                const col_name = std.mem.span(col_namez)[1..]; // name without leading ":" or "$" or "@" or "?" (see https://www.sqlite.org/c3ref/bind_parameter_name.html)
                                inline for (params_fields) |field| {
                                    if (std.mem.eql(u8, field.name, col_name)) {
                                        const param = @field(params_ptr.*, field.name);
                                        try bindOneParameterPtr(stmt, param_index, &param);
                                        break;
                                    }
                                }
                            }
                        }
                    }
                },
                .@"union" => {
                    // for tagged unioin, bind active value recursively
                    if (params_type_info.@"union".tag_type) |tag_type| {
                        const params = params_ptr.*;
                        const active_tag_value = @intFromEnum(@as(tag_type, params));
                        inline for (@typeInfo(tag_type).@"enum".fields) |tag_field| {
                            if (active_tag_value == tag_field.value) {
                                const active_value = @field(params, tag_field.name);
                                return bindParametersPtr(stmt, &active_value);
                            }
                        }
                        @panic("unable to resolve tagged union value");
                    } else {
                        @compileError("cannot bind untagged union");
                    }
                },
                else => {
                    @compileError("bind not supported for type " ++ @typeName(TParams));
                },
            }
        },
        .slice => {
            // bind each by index
            for (params_ptr, 0..) |*param_ptr, index| {
                if (index >= param_count) break;
                try bindOneParameterPtr(stmt, @intCast(index + 1), param_ptr);
            }
        },
        else => {
            @compileError("expected pointer to one or slice but got " ++ @typeName(@TypeOf(params_ptr)));
        },
    }
}

fn RowReader(RowType: type) type {
    if (comptime std.meta.hasFn(RowType, "readSqlite3Row")) {
        return struct {
            stmt: ?*c.sqlite3_stmt,

            pub fn init(stmt: ?*c.sqlite3_stmt) @This() {
                return .{ .stmt = stmt };
            }

            pub fn read(self: @This()) Error!RowType {
                return RowType.readSqlite3Row(self.stmt);
            }
        };
    }

    const row_type_info = comptime @typeInfo(RowType);
    if (row_type_info == .@"struct") {
        // TODO: tuples, arrays, probably some others
        const row_fields = comptime row_type_info.@"struct".fields;
        return struct {
            stmt: ?*c.sqlite3_stmt,
            field_col_indexes: [row_fields.len]c_int,

            pub fn init(stmt: ?*c.sqlite3_stmt) @This() {
                var field_col_indexes = [_]c_int{-1} ** row_fields.len;

                if (row_fields.len != 0) {
                    // maps field name to field index; comptime initialized
                    var field_lookup = comptime blk: {
                        const KV = struct { []const u8, usize };
                        var entries: [row_fields.len]KV = undefined;
                        for (row_fields, 0..) |field, field_index| {
                            entries[field_index] = KV{ field.name, field_index };
                        }
                        break :blk std.StaticStringMap(usize).initComptime(entries);
                    };

                    // based on field_lookup and columns of the query, initialize
                    // field_col_indexes to map field index to query column index
                    if (stmt != null) {
                        const col_count = c.sqlite3_column_count(stmt);
                        var col_index: c_int = 0;
                        while (col_index != col_count) {
                            const col_name = c.sqlite3_column_name(stmt, col_index);
                            const col_name_slice: []const u8 = std.mem.span(col_name);

                            if (field_lookup.get(col_name_slice)) |field_index| {
                                field_col_indexes[field_index] = col_index;
                            }
                            col_index += 1;
                        }
                    }
                }

                return .{
                    .stmt = stmt,
                    .field_col_indexes = field_col_indexes,
                };
            }

            pub fn read(self: @This()) Error!RowType {
                var row: RowType = undefined;

                inline for (row_fields, 0..) |field, field_index| {
                    const col_index = self.field_col_indexes[field_index];
                    if (col_index != -1) {
                        @field(row, field.name) = try readColumn(field.type, self.stmt, col_index);
                    } else if (field.default_value_ptr) |default_value_ptr| {
                        const dvalue_aligned: *align(field.alignment) const anyopaque = @alignCast(default_value_ptr);
                        @field(row, field.name) = @as(*const field.type, @ptrCast(dvalue_aligned)).*;
                    } else {
                        return Error.UndefinedField;
                    }
                }

                return row;
            }
        };
    } else {
        return struct {
            stmt: ?*c.sqlite3_stmt,

            pub fn init(stmt: ?*c.sqlite3_stmt) @This() {
                return .{ .stmt = stmt };
            }

            pub fn read(self: @This()) Error!RowType {
                return readColumn(RowType, self.stmt, 0);
            }
        };
    }
}

fn AllocRowReader(RowType: type) type {
    return struct {
        allocator: std.mem.Allocator,
        stmt: ?*c.sqlite3_stmt,

        pub fn init(allocator: std.mem.Allocator, stmt: ?*c.sqlite3_stmt) @This() {
            return .{ .allocator = allocator, .stmt = stmt };
        }

        pub fn read(self: @This()) Error!RowType {
            _ = self;
            @compileError("NYI");
        }
    };
}

const PreparedStatements = struct {
    stmt: ?*c.sqlite3_stmt,
    tail: []const u8,

    pub fn init(db: ?*c.sqlite3, sql: []const u8) Error!@This() {
        if (sql.len == 0) {
            return .{ .stmt = null, .tail = sql };
        }

        var stmt: ?*c.sqlite3_stmt = null;
        var p_tail: [*c]const u8 = null;
        try ok(c.sqlite3_prepare_v2(db, sql.ptr, @as(c_int, @intCast(sql.len)), &stmt, &p_tail));
        const tail = sql[@as(usize, @intFromPtr(p_tail)) - @as(usize, @intFromPtr(sql.ptr)) ..];

        return .{ .stmt = stmt, .tail = tail };
    }

    pub fn deinit(self: @This()) void {
        _ = c.sqlite3_finalize(self.stmt);
    }

    pub fn next(self: *@This()) Error!?*c.sqlite3_stmt {
        const stmt = self.stmt;
        if (stmt != null) {
            self.* = try init(c.sqlite3_db_handle(stmt), self.tail);
        }
        return stmt;
    }
};

/// Iterator to read values from statements.
/// Can also be used to iterate through a series of SQL statements,
/// preparing, stepping through, and finalizing each one in turn.
///
/// You will typically use `rowIterator`(), `exec`() or `ptrExec`() to obtain one
/// of these iterators.
///
/// See `rowIterator`(), `exec`() and `ptrExec`() for details.
pub fn RowIterator(RowType: type) type {
    return struct {
        row_reader: RowReader(RowType),
        remainder: ?PreparedStatements = null,

        /// Ensures statements prepared by the iterator are finalized.
        ///
        /// (The iterator returned by `exec`() and `ptrExec`() prepares statements,
        /// but the one returned from `rowIterator`() does not.)
        pub fn deinit(self: *@This()) void {
            if (self.remainder) |remainder| {
                _ = c.sqlite3_finalize(self.row_reader.stmt);
                self.row_reader.stmt = null;
                self.remainder = null;
                remainder.deinit();
            }
        }

        /// Returns the next result row.
        ///
        /// This calls `sqlite3_step` on the current statement and either returns the result using `readRow`()
        /// or null, as appropriate.
        ///
        /// For iterators on multiple statements, this automatically moves to the next statment when the current
        /// one is done, and returns null when the final one is one. (It takes care of calling sqlite3_prepare_v2
        /// on the next statement, and calls sqlite3_finalize on statements it prepares when it is done with them.)
        pub fn next(self: *@This()) Error!?RowType {
            while (true) {
                if (self.row_reader.stmt == null) {
                    // advance to the next statement, if any
                    if (self.remainder) |*remainder| {
                        const stmt = try remainder.next();
                        if (stmt == null) {
                            self.deinit();
                            return null;
                        }
                        self.row_reader = RowReader(RowType).init(stmt);
                    } else {
                        return null;
                    }
                }

                const step_rc = c.sqlite3_step(self.row_reader.stmt);

                switch (step_rc) {
                    c.SQLITE_DONE => {
                        // no more rows

                        // finalize the current statement if owned by the iterator
                        if (self.remainder != null) {
                            _ = c.sqlite3_finalize(self.row_reader.stmt);
                            self.row_reader.stmt = null;
                        }

                        continue;
                    },
                    c.SQLITE_ROW => {
                        // there's a row; read and return it
                        errdefer self.deinit();
                        return try self.row_reader.read();
                    },
                    else => {
                        self.deinit();
                        return rcErr(step_rc);
                    },
                }
            }
        }

        /// Runs the iterator to completion without returning a result.
        pub fn run(self: *@This()) Error!void {
            defer self.deinit();
            while (try self.next()) |_| {}
        }

        /// Returns the next result, if there is one.
        /// This executes only one step, but the iterator is done after this returns.
        pub fn getOptional(self: *@This()) Error!?RowType {
            defer self.deinit();
            return self.next();
        }

        /// Returns the next result, or error.NoResult if there is none.
        /// This executes only one step, but the iterator is done after this returns.
        pub fn get(self: *@This()) Error!RowType {
            if (try self.getOptional()) |row| {
                return row;
            }
            return Error.NoResult;
        }
    };
}

/// Iterator to read values from statements, where the values can have memory allocated to them.
/// Can also be used to iterate through a series of SQL statements,
/// preparing, stepping through, and finalizing each one in turn.
///
/// You will typically use `allocRowIterator`() or `allocExec`() to obtain one of these iterators.
///
/// See `allocRowIterator`() and `allocExec`() for details.
pub fn AllocRowIterator(RowType: type) type {
    return struct {
        row_reader: AllocRowReader(RowType),
        remainder: ?PreparedStatements = null,
        exec_args_mem: ?std.heap.ArenaAllocator,

        /// Ensures statements prepared by the iterator are finalized and
        /// any memory allocated for `sql` and `params` used when creating
        /// the iterator via `allocExec`() are freed.
        ///
        /// (The iterator returned by `allocExec`() and `allocExceptArgsExec`() prepares statements,
        /// but the one returned from `allocRowIterator`() does not.)
        pub fn deinit(self: *@This()) void {
            if (self.remainder) |remainder| {
                _ = c.sqlite3_finalize(self.row_reader.stmt);
                self.row_reader.stmt = null;
                remainder.deinit();
                .self.remainder = null;
            }
            if (self.exec_args_mem) |exec_args_mem| {
                exec_args_mem.deinit();
                self.exec_args_mem = null;
            }
        }

        /// Returns the next result row.
        ///
        /// This calls `sqlite3_step` on the current statement and either returns the result using `allocReadRow`()
        /// or null, as appropriate.
        ///
        /// For iterators on multiple statements, this automatically moves to the next statment when the current
        /// one is done, and returns null when the final one is one. (It takes care of calling sqlite3_prepare_v2
        /// on the next statement, and calls sqlite3_finalize on statements it prepares when it is done with them.)
        pub fn next(self: *@This()) Error!?RowType {
            while (true) {
                if (self.row_reader.stmt == null) {
                    // advance to the next statement, if any
                    if (self.remainder) |*remainder| {
                        const stmt = try remainder.next();
                        if (stmt == null) {
                            self.deinit();
                            return null;
                        }
                        self.row_reader = AllocRowReader(RowType).init(self.row_reader.allocator, stmt);
                    } else {
                        return null;
                    }
                }

                const step_rc = c.sqlite3_step(self.row_reader.stmt);

                switch (step_rc) {
                    c.SQLITE_DONE => {
                        // no more rows

                        // finalize the current statement if owned by the iterator
                        if (self.remainder != null) {
                            _ = c.sqlite3_finalize(self.row_reader.stmt);
                            self.row_reader.stmt = null;
                        }

                        continue;
                    },
                    c.SQLITE_ROW => {
                        // there's a row; read and return it
                        errdefer self.deinit();
                        return try self.row_reader.read();
                    },
                    else => {
                        self.deinit();
                        return rcErr(step_rc);
                    },
                }
            }
        }

        /// Runs the iterator to completion without returning a result.
        pub fn run(self: *@This()) Error!void {
            defer self.deinit();
            while (try self.next()) |_| {}
        }

        /// Returns the next result, if there is one.
        /// This executes only one step, but the iterator is done after this returns.
        pub fn getOptional(self: *@This()) Error!?RowType {
            defer self.deinit();
            return self.next();
        }

        /// Returns the next result, or error.NoResult if there is none.
        /// This executes only one step, but the iterator is done after this returns.
        pub fn get(self: *@This()) Error!RowType {
            if (try self.getOptional()) |row| {
                return row;
            }
            return Error.NoResult;
        }
    };
}

/// Each SqliteError corresponds to the sqlite result code of the same name.
/// See https://www.sqlite.org/rescode.html
pub const SqliteError = error{
    SQLITE_OK,
    SQLITE_ERROR,
    SQLITE_INTERNAL,
    SQLITE_PERM,
    SQLITE_ABORT,
    SQLITE_BUSY,
    SQLITE_LOCKED,
    SQLITE_NOMEM,
    SQLITE_READONLY,
    SQLITE_INTERRUPT,
    SQLITE_IOERR,
    SQLITE_CORRUPT,
    SQLITE_NOTFOUND,
    SQLITE_FULL,
    SQLITE_CANTOPEN,
    SQLITE_PROTOCOL,
    SQLITE_EMPTY,
    SQLITE_SCHEMA,
    SQLITE_TOOBIG,
    SQLITE_CONSTRAINT,
    SQLITE_MISMATCH,
    SQLITE_MISUSE,
    SQLITE_NOLFS,
    SQLITE_AUTH,
    SQLITE_FORMAT,
    SQLITE_RANGE,
    SQLITE_NOTADB,
    SQLITE_NOTICE,
    SQLITE_WARNING,
    SQLITE_ROW,
    SQLITE_DONE,
    SQLITE_ERROR_MISSING_COLLSEQ,
    SQLITE_ERROR_RETRY,
    SQLITE_ERROR_SNAPSHOT,
    SQLITE_IOERR_READ,
    SQLITE_IOERR_SHORT_READ,
    SQLITE_IOERR_WRITE,
    SQLITE_IOERR_FSYNC,
    SQLITE_IOERR_DIR_FSYNC,
    SQLITE_IOERR_TRUNCATE,
    SQLITE_IOERR_FSTAT,
    SQLITE_IOERR_UNLOCK,
    SQLITE_IOERR_RDLOCK,
    SQLITE_IOERR_DELETE,
    SQLITE_IOERR_BLOCKED,
    SQLITE_IOERR_NOMEM,
    SQLITE_IOERR_ACCESS,
    SQLITE_IOERR_CHECKRESERVEDLOCK,
    SQLITE_IOERR_LOCK,
    SQLITE_IOERR_CLOSE,
    SQLITE_IOERR_DIR_CLOSE,
    SQLITE_IOERR_SHMOPEN,
    SQLITE_IOERR_SHMSIZE,
    SQLITE_IOERR_SHMLOCK,
    SQLITE_IOERR_SHMMAP,
    SQLITE_IOERR_SEEK,
    SQLITE_IOERR_DELETE_NOENT,
    SQLITE_IOERR_MMAP,
    SQLITE_IOERR_GETTEMPPATH,
    SQLITE_IOERR_CONVPATH,
    SQLITE_IOERR_VNODE,
    SQLITE_IOERR_AUTH,
    SQLITE_IOERR_BEGIN_ATOMIC,
    SQLITE_IOERR_COMMIT_ATOMIC,
    SQLITE_IOERR_ROLLBACK_ATOMIC,
    SQLITE_IOERR_DATA,
    SQLITE_IOERR_CORRUPTFS,
    SQLITE_IOERR_IN_PAGE,
    SQLITE_LOCKED_SHAREDCACHE,
    SQLITE_LOCKED_VTAB,
    SQLITE_BUSY_RECOVERY,
    SQLITE_BUSY_SNAPSHOT,
    SQLITE_BUSY_TIMEOUT,
    SQLITE_CANTOPEN_NOTEMPDIR,
    SQLITE_CANTOPEN_ISDIR,
    SQLITE_CANTOPEN_FULLPATH,
    SQLITE_CANTOPEN_CONVPATH,
    SQLITE_CANTOPEN_DIRTYWAL,
    SQLITE_CANTOPEN_SYMLINK,
    SQLITE_CORRUPT_VTAB,
    SQLITE_CORRUPT_SEQUENCE,
    SQLITE_CORRUPT_INDEX,
    SQLITE_READONLY_RECOVERY,
    SQLITE_READONLY_CANTLOCK,
    SQLITE_READONLY_ROLLBACK,
    SQLITE_READONLY_DBMOVED,
    SQLITE_READONLY_CANTINIT,
    SQLITE_READONLY_DIRECTORY,
    SQLITE_ABORT_ROLLBACK,
    SQLITE_CONSTRAINT_CHECK,
    SQLITE_CONSTRAINT_COMMITHOOK,
    SQLITE_CONSTRAINT_FOREIGNKEY,
    SQLITE_CONSTRAINT_FUNCTION,
    SQLITE_CONSTRAINT_NOTNULL,
    SQLITE_CONSTRAINT_PRIMARYKEY,
    SQLITE_CONSTRAINT_TRIGGER,
    SQLITE_CONSTRAINT_UNIQUE,
    SQLITE_CONSTRAINT_VTAB,
    SQLITE_CONSTRAINT_ROWID,
    SQLITE_CONSTRAINT_PINNED,
    SQLITE_CONSTRAINT_DATATYPE,
    SQLITE_NOTICE_RECOVER_WAL,
    SQLITE_NOTICE_RECOVER_ROLLBACK,
    SQLITE_NOTICE_RBU,
    SQLITE_WARNING_AUTOINDEX,
    SQLITE_AUTH_USER,
    SQLITE_OK_LOAD_PERMANENTLY,
    SQLITE_OK_SYMLINK,
    /// Used when an unknown result code is converted to an error.
    UnknownSqliteResultCode,
};

fn rcErr(rc: c_int) SqliteError {
    return switch (rc) {
        c.SQLITE_OK => SqliteError.SQLITE_OK,
        c.SQLITE_ERROR => SqliteError.SQLITE_ERROR,
        c.SQLITE_INTERNAL => SqliteError.SQLITE_INTERNAL,
        c.SQLITE_PERM => SqliteError.SQLITE_PERM,
        c.SQLITE_ABORT => SqliteError.SQLITE_ABORT,
        c.SQLITE_BUSY => SqliteError.SQLITE_BUSY,
        c.SQLITE_LOCKED => SqliteError.SQLITE_LOCKED,
        c.SQLITE_NOMEM => SqliteError.SQLITE_NOMEM,
        c.SQLITE_READONLY => SqliteError.SQLITE_READONLY,
        c.SQLITE_INTERRUPT => SqliteError.SQLITE_INTERRUPT,
        c.SQLITE_IOERR => SqliteError.SQLITE_IOERR,
        c.SQLITE_CORRUPT => SqliteError.SQLITE_CORRUPT,
        c.SQLITE_NOTFOUND => SqliteError.SQLITE_NOTFOUND,
        c.SQLITE_FULL => SqliteError.SQLITE_FULL,
        c.SQLITE_CANTOPEN => SqliteError.SQLITE_CANTOPEN,
        c.SQLITE_PROTOCOL => SqliteError.SQLITE_PROTOCOL,
        c.SQLITE_EMPTY => SqliteError.SQLITE_EMPTY,
        c.SQLITE_SCHEMA => SqliteError.SQLITE_SCHEMA,
        c.SQLITE_TOOBIG => SqliteError.SQLITE_TOOBIG,
        c.SQLITE_CONSTRAINT => SqliteError.SQLITE_CONSTRAINT,
        c.SQLITE_MISMATCH => SqliteError.SQLITE_MISMATCH,
        c.SQLITE_MISUSE => SqliteError.SQLITE_MISUSE,
        c.SQLITE_NOLFS => SqliteError.SQLITE_NOLFS,
        c.SQLITE_AUTH => SqliteError.SQLITE_AUTH,
        c.SQLITE_FORMAT => SqliteError.SQLITE_FORMAT,
        c.SQLITE_RANGE => SqliteError.SQLITE_RANGE,
        c.SQLITE_NOTADB => SqliteError.SQLITE_NOTADB,
        c.SQLITE_NOTICE => SqliteError.SQLITE_NOTICE,
        c.SQLITE_WARNING => SqliteError.SQLITE_WARNING,
        c.SQLITE_ROW => SqliteError.SQLITE_ROW,
        c.SQLITE_DONE => SqliteError.SQLITE_DONE,
        c.SQLITE_ERROR_MISSING_COLLSEQ => SqliteError.SQLITE_ERROR_MISSING_COLLSEQ,
        c.SQLITE_ERROR_RETRY => SqliteError.SQLITE_ERROR_RETRY,
        c.SQLITE_ERROR_SNAPSHOT => SqliteError.SQLITE_ERROR_SNAPSHOT,
        c.SQLITE_IOERR_READ => SqliteError.SQLITE_IOERR_READ,
        c.SQLITE_IOERR_SHORT_READ => SqliteError.SQLITE_IOERR_SHORT_READ,
        c.SQLITE_IOERR_WRITE => SqliteError.SQLITE_IOERR_WRITE,
        c.SQLITE_IOERR_FSYNC => SqliteError.SQLITE_IOERR_FSYNC,
        c.SQLITE_IOERR_DIR_FSYNC => SqliteError.SQLITE_IOERR_DIR_FSYNC,
        c.SQLITE_IOERR_TRUNCATE => SqliteError.SQLITE_IOERR_TRUNCATE,
        c.SQLITE_IOERR_FSTAT => SqliteError.SQLITE_IOERR_FSTAT,
        c.SQLITE_IOERR_UNLOCK => SqliteError.SQLITE_IOERR_UNLOCK,
        c.SQLITE_IOERR_RDLOCK => SqliteError.SQLITE_IOERR_RDLOCK,
        c.SQLITE_IOERR_DELETE => SqliteError.SQLITE_IOERR_DELETE,
        c.SQLITE_IOERR_BLOCKED => SqliteError.SQLITE_IOERR_BLOCKED,
        c.SQLITE_IOERR_NOMEM => SqliteError.SQLITE_IOERR_NOMEM,
        c.SQLITE_IOERR_ACCESS => SqliteError.SQLITE_IOERR_ACCESS,
        c.SQLITE_IOERR_CHECKRESERVEDLOCK => SqliteError.SQLITE_IOERR_CHECKRESERVEDLOCK,
        c.SQLITE_IOERR_LOCK => SqliteError.SQLITE_IOERR_LOCK,
        c.SQLITE_IOERR_CLOSE => SqliteError.SQLITE_IOERR_CLOSE,
        c.SQLITE_IOERR_DIR_CLOSE => SqliteError.SQLITE_IOERR_DIR_CLOSE,
        c.SQLITE_IOERR_SHMOPEN => SqliteError.SQLITE_IOERR_SHMOPEN,
        c.SQLITE_IOERR_SHMSIZE => SqliteError.SQLITE_IOERR_SHMSIZE,
        c.SQLITE_IOERR_SHMLOCK => SqliteError.SQLITE_IOERR_SHMLOCK,
        c.SQLITE_IOERR_SHMMAP => SqliteError.SQLITE_IOERR_SHMMAP,
        c.SQLITE_IOERR_SEEK => SqliteError.SQLITE_IOERR_SEEK,
        c.SQLITE_IOERR_DELETE_NOENT => SqliteError.SQLITE_IOERR_DELETE_NOENT,
        c.SQLITE_IOERR_MMAP => SqliteError.SQLITE_IOERR_MMAP,
        c.SQLITE_IOERR_GETTEMPPATH => SqliteError.SQLITE_IOERR_GETTEMPPATH,
        c.SQLITE_IOERR_CONVPATH => SqliteError.SQLITE_IOERR_CONVPATH,
        c.SQLITE_IOERR_VNODE => SqliteError.SQLITE_IOERR_VNODE,
        c.SQLITE_IOERR_AUTH => SqliteError.SQLITE_IOERR_AUTH,
        c.SQLITE_IOERR_BEGIN_ATOMIC => SqliteError.SQLITE_IOERR_BEGIN_ATOMIC,
        c.SQLITE_IOERR_COMMIT_ATOMIC => SqliteError.SQLITE_IOERR_COMMIT_ATOMIC,
        c.SQLITE_IOERR_ROLLBACK_ATOMIC => SqliteError.SQLITE_IOERR_ROLLBACK_ATOMIC,
        c.SQLITE_IOERR_DATA => SqliteError.SQLITE_IOERR_DATA,
        c.SQLITE_IOERR_CORRUPTFS => SqliteError.SQLITE_IOERR_CORRUPTFS,
        c.SQLITE_IOERR_IN_PAGE => SqliteError.SQLITE_IOERR_IN_PAGE,
        c.SQLITE_LOCKED_SHAREDCACHE => SqliteError.SQLITE_LOCKED_SHAREDCACHE,
        c.SQLITE_LOCKED_VTAB => SqliteError.SQLITE_LOCKED_VTAB,
        c.SQLITE_BUSY_RECOVERY => SqliteError.SQLITE_BUSY_RECOVERY,
        c.SQLITE_BUSY_SNAPSHOT => SqliteError.SQLITE_BUSY_SNAPSHOT,
        c.SQLITE_BUSY_TIMEOUT => SqliteError.SQLITE_BUSY_TIMEOUT,
        c.SQLITE_CANTOPEN_NOTEMPDIR => SqliteError.SQLITE_CANTOPEN_NOTEMPDIR,
        c.SQLITE_CANTOPEN_ISDIR => SqliteError.SQLITE_CANTOPEN_ISDIR,
        c.SQLITE_CANTOPEN_FULLPATH => SqliteError.SQLITE_CANTOPEN_FULLPATH,
        c.SQLITE_CANTOPEN_CONVPATH => SqliteError.SQLITE_CANTOPEN_CONVPATH,
        c.SQLITE_CANTOPEN_DIRTYWAL => SqliteError.SQLITE_CANTOPEN_DIRTYWAL,
        c.SQLITE_CANTOPEN_SYMLINK => SqliteError.SQLITE_CANTOPEN_SYMLINK,
        c.SQLITE_CORRUPT_VTAB => SqliteError.SQLITE_CORRUPT_VTAB,
        c.SQLITE_CORRUPT_SEQUENCE => SqliteError.SQLITE_CORRUPT_SEQUENCE,
        c.SQLITE_CORRUPT_INDEX => SqliteError.SQLITE_CORRUPT_INDEX,
        c.SQLITE_READONLY_RECOVERY => SqliteError.SQLITE_READONLY_RECOVERY,
        c.SQLITE_READONLY_CANTLOCK => SqliteError.SQLITE_READONLY_CANTLOCK,
        c.SQLITE_READONLY_ROLLBACK => SqliteError.SQLITE_READONLY_ROLLBACK,
        c.SQLITE_READONLY_DBMOVED => SqliteError.SQLITE_READONLY_DBMOVED,
        c.SQLITE_READONLY_CANTINIT => SqliteError.SQLITE_READONLY_CANTINIT,
        c.SQLITE_READONLY_DIRECTORY => SqliteError.SQLITE_READONLY_DIRECTORY,
        c.SQLITE_ABORT_ROLLBACK => SqliteError.SQLITE_ABORT_ROLLBACK,
        c.SQLITE_CONSTRAINT_CHECK => SqliteError.SQLITE_CONSTRAINT_CHECK,
        c.SQLITE_CONSTRAINT_COMMITHOOK => SqliteError.SQLITE_CONSTRAINT_COMMITHOOK,
        c.SQLITE_CONSTRAINT_FOREIGNKEY => SqliteError.SQLITE_CONSTRAINT_FOREIGNKEY,
        c.SQLITE_CONSTRAINT_FUNCTION => SqliteError.SQLITE_CONSTRAINT_FUNCTION,
        c.SQLITE_CONSTRAINT_NOTNULL => SqliteError.SQLITE_CONSTRAINT_NOTNULL,
        c.SQLITE_CONSTRAINT_PRIMARYKEY => SqliteError.SQLITE_CONSTRAINT_PRIMARYKEY,
        c.SQLITE_CONSTRAINT_TRIGGER => SqliteError.SQLITE_CONSTRAINT_TRIGGER,
        c.SQLITE_CONSTRAINT_UNIQUE => SqliteError.SQLITE_CONSTRAINT_UNIQUE,
        c.SQLITE_CONSTRAINT_VTAB => SqliteError.SQLITE_CONSTRAINT_VTAB,
        c.SQLITE_CONSTRAINT_ROWID => SqliteError.SQLITE_CONSTRAINT_ROWID,
        c.SQLITE_CONSTRAINT_PINNED => SqliteError.SQLITE_CONSTRAINT_PINNED,
        c.SQLITE_CONSTRAINT_DATATYPE => SqliteError.SQLITE_CONSTRAINT_DATATYPE,
        c.SQLITE_NOTICE_RECOVER_WAL => SqliteError.SQLITE_NOTICE_RECOVER_WAL,
        c.SQLITE_NOTICE_RECOVER_ROLLBACK => SqliteError.SQLITE_NOTICE_RECOVER_ROLLBACK,
        c.SQLITE_NOTICE_RBU => SqliteError.SQLITE_NOTICE_RBU,
        c.SQLITE_WARNING_AUTOINDEX => SqliteError.SQLITE_WARNING_AUTOINDEX,
        c.SQLITE_AUTH_USER => SqliteError.SQLITE_AUTH_USER,
        c.SQLITE_OK_LOAD_PERMANENTLY => SqliteError.SQLITE_OK_LOAD_PERMANENTLY,
        c.SQLITE_OK_SYMLINK => SqliteError.SQLITE_OK_SYMLINK,
        else => SqliteError.UnknownSqliteResultCode,
    };
}

/// Converts an error code back to its corresponding sqlite result code.
/// Returns the general SQLITE_ERROR for any error that doesn't correspond
/// to a sqlite result code.
pub fn rcFromErr(err: Error) c_int {
    return switch (err) {
        .SQLITE_OK => c.SQLITE_OK,
        .SQLITE_ERROR => c.SQLITE_ERROR,
        .SQLITE_INTERNAL => c.SQLITE_INTERNAL,
        .SQLITE_PERM => c.SQLITE_PERM,
        .SQLITE_ABORT => c.SQLITE_ABORT,
        .SQLITE_BUSY => c.SQLITE_BUSY,
        .SQLITE_LOCKED => c.SQLITE_LOCKED,
        .SQLITE_NOMEM => c.SQLITE_NOMEM,
        .SQLITE_READONLY => c.SQLITE_READONLY,
        .SQLITE_INTERRUPT => c.SQLITE_INTERRUPT,
        .SQLITE_IOERR => c.SQLITE_IOERR,
        .SQLITE_CORRUPT => c.SQLITE_CORRUPT,
        .SQLITE_NOTFOUND => c.SQLITE_NOTFOUND,
        .SQLITE_FULL => c.SQLITE_FULL,
        .SQLITE_CANTOPEN => c.SQLITE_CANTOPEN,
        .SQLITE_PROTOCOL => c.SQLITE_PROTOCOL,
        .SQLITE_EMPTY => c.SQLITE_EMPTY,
        .SQLITE_SCHEMA => c.SQLITE_SCHEMA,
        .SQLITE_TOOBIG => c.SQLITE_TOOBIG,
        .SQLITE_CONSTRAINT => c.SQLITE_CONSTRAINT,
        .SQLITE_MISMATCH => c.SQLITE_MISMATCH,
        .SQLITE_MISUSE => c.SQLITE_MISUSE,
        .SQLITE_NOLFS => c.SQLITE_NOLFS,
        .SQLITE_AUTH => c.SQLITE_AUTH,
        .SQLITE_FORMAT => c.SQLITE_FORMAT,
        .SQLITE_RANGE => c.SQLITE_RANGE,
        .SQLITE_NOTADB => c.SQLITE_NOTADB,
        .SQLITE_NOTICE => c.SQLITE_NOTICE,
        .SQLITE_WARNING => c.SQLITE_WARNING,
        .SQLITE_ROW => c.SQLITE_ROW,
        .SQLITE_DONE => c.SQLITE_DONE,
        .SQLITE_ERROR_MISSING_COLLSEQ => c.SQLITE_ERROR_MISSING_COLLSEQ,
        .SQLITE_ERROR_RETRY => c.SQLITE_ERROR_RETRY,
        .SQLITE_ERROR_SNAPSHOT => c.SQLITE_ERROR_SNAPSHOT,
        .SQLITE_IOERR_READ => c.SQLITE_IOERR_READ,
        .SQLITE_IOERR_SHORT_READ => c.SQLITE_IOERR_SHORT_READ,
        .SQLITE_IOERR_WRITE => c.SQLITE_IOERR_WRITE,
        .SQLITE_IOERR_FSYNC => c.SQLITE_IOERR_FSYNC,
        .SQLITE_IOERR_DIR_FSYNC => c.SQLITE_IOERR_DIR_FSYNC,
        .SQLITE_IOERR_TRUNCATE => c.SQLITE_IOERR_TRUNCATE,
        .SQLITE_IOERR_FSTAT => c.SQLITE_IOERR_FSTAT,
        .SQLITE_IOERR_UNLOCK => c.SQLITE_IOERR_UNLOCK,
        .SQLITE_IOERR_RDLOCK => c.SQLITE_IOERR_RDLOCK,
        .SQLITE_IOERR_DELETE => c.SQLITE_IOERR_DELETE,
        .SQLITE_IOERR_BLOCKED => c.SQLITE_IOERR_BLOCKED,
        .SQLITE_IOERR_NOMEM => c.SQLITE_IOERR_NOMEM,
        .SQLITE_IOERR_ACCESS => c.SQLITE_IOERR_ACCESS,
        .SQLITE_IOERR_CHECKRESERVEDLOCK => c.SQLITE_IOERR_CHECKRESERVEDLOCK,
        .SQLITE_IOERR_LOCK => c.SQLITE_IOERR_LOCK,
        .SQLITE_IOERR_CLOSE => c.SQLITE_IOERR_CLOSE,
        .SQLITE_IOERR_DIR_CLOSE => c.SQLITE_IOERR_DIR_CLOSE,
        .SQLITE_IOERR_SHMOPEN => c.SQLITE_IOERR_SHMOPEN,
        .SQLITE_IOERR_SHMSIZE => c.SQLITE_IOERR_SHMSIZE,
        .SQLITE_IOERR_SHMLOCK => c.SQLITE_IOERR_SHMLOCK,
        .SQLITE_IOERR_SHMMAP => c.SQLITE_IOERR_SHMMAP,
        .SQLITE_IOERR_SEEK => c.SQLITE_IOERR_SEEK,
        .SQLITE_IOERR_DELETE_NOENT => c.SQLITE_IOERR_DELETE_NOENT,
        .SQLITE_IOERR_MMAP => c.SQLITE_IOERR_MMAP,
        .SQLITE_IOERR_GETTEMPPATH => c.SQLITE_IOERR_GETTEMPPATH,
        .SQLITE_IOERR_CONVPATH => c.SQLITE_IOERR_CONVPATH,
        .SQLITE_IOERR_VNODE => c.SQLITE_IOERR_VNODE,
        .SQLITE_IOERR_AUTH => c.SQLITE_IOERR_AUTH,
        .SQLITE_IOERR_BEGIN_ATOMIC => c.SQLITE_IOERR_BEGIN_ATOMIC,
        .SQLITE_IOERR_COMMIT_ATOMIC => c.SQLITE_IOERR_COMMIT_ATOMIC,
        .SQLITE_IOERR_ROLLBACK_ATOMIC => c.SQLITE_IOERR_ROLLBACK_ATOMIC,
        .SQLITE_IOERR_DATA => c.SQLITE_IOERR_DATA,
        .SQLITE_IOERR_CORRUPTFS => c.SQLITE_IOERR_CORRUPTFS,
        .SQLITE_IOERR_IN_PAGE => c.SQLITE_IOERR_IN_PAGE,
        .SQLITE_LOCKED_SHAREDCACHE => c.SQLITE_LOCKED_SHAREDCACHE,
        .SQLITE_LOCKED_VTAB => c.SQLITE_LOCKED_VTAB,
        .SQLITE_BUSY_RECOVERY => c.SQLITE_BUSY_RECOVERY,
        .SQLITE_BUSY_SNAPSHOT => c.SQLITE_BUSY_SNAPSHOT,
        .SQLITE_BUSY_TIMEOUT => c.SQLITE_BUSY_TIMEOUT,
        .SQLITE_CANTOPEN_NOTEMPDIR => c.SQLITE_CANTOPEN_NOTEMPDIR,
        .SQLITE_CANTOPEN_ISDIR => c.SQLITE_CANTOPEN_ISDIR,
        .SQLITE_CANTOPEN_FULLPATH => c.SQLITE_CANTOPEN_FULLPATH,
        .SQLITE_CANTOPEN_CONVPATH => c.SQLITE_CANTOPEN_CONVPATH,
        .SQLITE_CANTOPEN_DIRTYWAL => c.SQLITE_CANTOPEN_DIRTYWAL,
        .SQLITE_CANTOPEN_SYMLINK => c.SQLITE_CANTOPEN_SYMLINK,
        .SQLITE_CORRUPT_VTAB => c.SQLITE_CORRUPT_VTAB,
        .SQLITE_CORRUPT_SEQUENCE => c.SQLITE_CORRUPT_SEQUENCE,
        .SQLITE_CORRUPT_INDEX => c.SQLITE_CORRUPT_INDEX,
        .SQLITE_READONLY_RECOVERY => c.SQLITE_READONLY_RECOVERY,
        .SQLITE_READONLY_CANTLOCK => c.SQLITE_READONLY_CANTLOCK,
        .SQLITE_READONLY_ROLLBACK => c.SQLITE_READONLY_ROLLBACK,
        .SQLITE_READONLY_DBMOVED => c.SQLITE_READONLY_DBMOVED,
        .SQLITE_READONLY_CANTINIT => c.SQLITE_READONLY_CANTINIT,
        .SQLITE_READONLY_DIRECTORY => c.SQLITE_READONLY_DIRECTORY,
        .SQLITE_ABORT_ROLLBACK => c.SQLITE_ABORT_ROLLBACK,
        .SQLITE_CONSTRAINT_CHECK => c.SQLITE_CONSTRAINT_CHECK,
        .SQLITE_CONSTRAINT_COMMITHOOK => c.SQLITE_CONSTRAINT_COMMITHOOK,
        .SQLITE_CONSTRAINT_FOREIGNKEY => c.SQLITE_CONSTRAINT_FOREIGNKEY,
        .SQLITE_CONSTRAINT_FUNCTION => c.SQLITE_CONSTRAINT_FUNCTION,
        .SQLITE_CONSTRAINT_NOTNULL => c.SQLITE_CONSTRAINT_NOTNULL,
        .SQLITE_CONSTRAINT_PRIMARYKEY => c.SQLITE_CONSTRAINT_PRIMARYKEY,
        .SQLITE_CONSTRAINT_TRIGGER => c.SQLITE_CONSTRAINT_TRIGGER,
        .SQLITE_CONSTRAINT_UNIQUE => c.SQLITE_CONSTRAINT_UNIQUE,
        .SQLITE_CONSTRAINT_VTAB => c.SQLITE_CONSTRAINT_VTAB,
        .SQLITE_CONSTRAINT_ROWID => c.SQLITE_CONSTRAINT_ROWID,
        .SQLITE_CONSTRAINT_PINNED => c.SQLITE_CONSTRAINT_PINNED,
        .SQLITE_CONSTRAINT_DATATYPE => c.SQLITE_CONSTRAINT_DATATYPE,
        .SQLITE_NOTICE_RECOVER_WAL => c.SQLITE_NOTICE_RECOVER_WAL,
        .SQLITE_NOTICE_RECOVER_ROLLBACK => c.SQLITE_NOTICE_RECOVER_ROLLBACK,
        .SQLITE_NOTICE_RBU => c.SQLITE_NOTICE_RBU,
        .SQLITE_WARNING_AUTOINDEX => c.SQLITE_WARNING_AUTOINDEX,
        .SQLITE_AUTH_USER => c.SQLITE_AUTH_USER,
        .SQLITE_OK_LOAD_PERMANENTLY => c.SQLITE_OK_LOAD_PERMANENTLY,
        .SQLITE_OK_SYMLINK => c.SQLITE_OK_SYMLINK,
        else => c.SQLITE_ERROR, // convert anything else to a general error
    };
}
