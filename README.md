**mite**: A sqlite3 "unwrapper":

Implements zig idioms for sqlite, without hiding or duplicating sqlite's comprehensive API.

--------------------

### • Map sqlite error codes to zig errors

fn `ok`(rc: c_int) `SqliteError`!void

--------------------

### • Bind arbitrary values, structs, tuples, etc. as parameters to a prepared sqlite statement

    fn `bindParameters`(stmt: ?*sqlite3_stmt, params: anytype) Error!void
    
    fn `allocBindParameters`(allocator: Allocator, stmt: ?*sqlite3_stmt, params: anytype) Error!void
    
    fn `bindOneParameter`(stmt: ?*sqlite3_stmt, param_index: c_int, param: anytype) Error!void
    
    fn `allocBindOneParameter`(allocator: Allocator, stmt: ?*sqlite3_stmt, param_index: c_int,
          param: anytype) Error!void
          
    (customizable)

--------------------

### • Read values of arbitrary types from a sqlite statement

    fn `readRow`(RowType: type, stmt: ?*sqlite3_stmt) Error!RowType
    
    fn `allocReadRow`(RowType: type, allocator: Allocator, stmt: ?*sqlite3_stmt) Error!RowType
    
    fn `readColumn`(T: type, stmt: ?*sqlite3_stmt, col_index: c_int) Error!T
    
    fn `allocReadColumn`(T: type, allocator: Allocator, stmt: ?*sqlite3_stmt, col_index: c_int)
        Error!T
        
    (customizable)

--------------------

### • Use zig iterators to step through statement results

    fn `rowIterator`(RowType: type, stmt: ?*sqlite3_stmt) `RowIterator`(RowType)
    
    fn `allocRowIterator`(RowType: type, allocator: Allocator, stmt: ?*sqlite3_stmt)
        `AllocRowIterator`(RowType)

--------------------

### • Put it all together

Execute multiple statements, bind arbitraty parameters, and
receive results of an arbitrary type using zig iterators:

    fn `exec`(RowType: type, db: ?*sqlite3, sql: []const u8, params: anytype) Error!RowIterator(RowType)
    
    fn `ptrExec`(RowType: type, db: ?*sqlite3, sql: []const u8, params: anytype)
        Error!`RowIterator`(RowType)
        
    fn `allocExec`(RowType: type, allocator: Allocator, db: ?*sqlite3, sql: []const u8, params: anytype)
        Error!`AllocRowIterator`(RowType)
        
    The variants support different memory management options. (There's also `allocExceptArgsExec`())

--------------------

Additionally, you can:

* customize binding by implementing `miteBindParameters`,
    `miteAllocBindParameters`, `miteBindOneParameter` or `miteAllocBindOneParameter`.

* customize reading by implementing `miteReadRow`,
  `miteAllocReadRow`, `miteReadColumn` or `miteAllocReadColumn`.

* use convenience functions for common cases:
  * `run`() steps through statements to completion when no result is needed
  * `get`() and `allocGet`() return the first result from executing one or more statements
  * `getOptional`() and `allocGetOptional`() returns the first result if there is one
  * similar functions are also available on the row iterators

* use the provided zig tagged unions to hold values of the native sqlite3 types:

const `Value` = union(enum) {
    INTEGER: i64, FLOAT: f64, TEXT: []const u8, BLOB: []const u8, NULL, ... };

const `AllocValue` = struct {
    allocator: Allocator, value: Value, ... };

...and a few related utilities and helpers.

