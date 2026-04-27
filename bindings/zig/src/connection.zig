const std = @import("std");
const c = @import("c.zig");
const err = @import("error.zig");
const statement_mod = @import("statement.zig");
const value_mod = @import("value.zig");

/// Result of preparing the first statement from multi-statement SQL as a value handle.
pub const PrepareFirstResult = struct {
    /// The prepared statement, or null if no statements could be parsed.
    statement: ?statement_mod.Statement,
    /// Byte offset in sql right after the parsed statement.
    tail_idx: usize,
};

pub const Column = struct {
    name: []u8,
    decltype: []u8,

    pub fn deinit(self: *Column, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.decltype);
    }
};

pub const Row = struct {
    values: []value_mod.OwnedValue,

    pub fn deinit(self: *Row, allocator: std.mem.Allocator) void {
        for (self.values) |*value| {
            value.deinit(allocator);
        }
        allocator.free(self.values);
    }
};

/// Borrowed view of the current row. Text and blob slices are valid until the
/// owning `Rows` is stepped again, reset, or deinitialized.
pub const RowView = struct {
    stmt: *statement_mod.Statement,
    column_count: usize,

    pub fn len(self: RowView) usize {
        return self.column_count;
    }

    pub fn valueKind(self: RowView, index: usize) err.TursoError!value_mod.ValueKind {
        return self.stmt.rowValueKindChecked(index);
    }

    pub fn int(self: RowView, index: usize) err.TursoError!i64 {
        return self.stmt.rowValueIntChecked(index);
    }

    pub fn double(self: RowView, index: usize) err.TursoError!f64 {
        return self.stmt.rowValueDoubleChecked(index);
    }

    pub fn text(self: RowView, index: usize) err.TursoError![]const u8 {
        if (self.stmt.ptr == null) return err.mapStatus(c.TURSO_MISUSE, null, self.stmt.allocator);
        return value_mod.readBytesBorrowed(self.stmt.ptr.?, index);
    }

    pub fn blob(self: RowView, index: usize) err.TursoError![]const u8 {
        if (self.stmt.ptr == null) return err.mapStatus(c.TURSO_MISUSE, null, self.stmt.allocator);
        return value_mod.readBytesBorrowed(self.stmt.ptr.?, index);
    }

    pub fn borrowedValue(self: RowView, index: usize) err.TursoError!value_mod.BorrowedValue {
        return switch (try self.valueKind(index)) {
            .integer => .{ .integer = try self.int(index) },
            .real => .{ .real = try self.double(index) },
            .text => .{ .text = try self.text(index) },
            .blob => .{ .blob = try self.blob(index) },
            .null => .{ .null = {} },
            .unknown => .{ .unknown = {} },
        };
    }

    pub fn ownedValue(self: RowView, index: usize) !value_mod.OwnedValue {
        return self.stmt.rowValue(index);
    }
};

/// Streaming row iterator. Owns the prepared statement backing row views.
pub const Rows = struct {
    stmt: statement_mod.Statement,
    column_count: usize,
    done: bool = false,

    pub fn next(self: *Rows) err.TursoError!?RowView {
        if (self.done) return null;

        return switch (try self.stmt.step()) {
            .TURSO_ROW => RowView{
                .stmt = &self.stmt,
                .column_count = self.column_count,
            },
            .TURSO_DONE => {
                self.done = true;
                return null;
            },
            else => err.mapStatus(c.TURSO_MISUSE, null, self.stmt.allocator),
        };
    }

    pub fn deinit(self: *Rows) void {
        self.stmt.finalize() catch {};
        self.stmt.deinit();
        self.done = true;
    }
};

pub const QueryResult = struct {
    columns: []Column,
    rows: []Row,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *QueryResult) void {
        for (self.columns) |*column| {
            column.deinit(self.allocator);
        }
        self.allocator.free(self.columns);

        for (self.rows) |*row| {
            row.deinit(self.allocator);
        }
        self.allocator.free(self.rows);
    }
};

pub const Transaction = struct {
    conn: *Connection,
    finished: bool = false,

    pub fn execute(self: *Transaction, sql: anytype) err.TursoError!u64 {
        return self.conn.execute(sql);
    }

    pub fn query(self: *Transaction, sql: anytype) err.TursoError!QueryResult {
        return self.conn.query(sql);
    }

    pub fn commit(self: *Transaction) err.TursoError!void {
        if (self.finished) {
            return err.mapStatus(c.TURSO_MISUSE, null, self.conn.allocator);
        }
        _ = try self.conn.execute("COMMIT");
        self.finished = true;
    }

    pub fn rollback(self: *Transaction) err.TursoError!void {
        if (self.finished) return;
        _ = try self.conn.execute("ROLLBACK");
        self.finished = true;
    }
};

/// Wrapper around `turso_connection_t` with Zig-friendly lifecycle management.
pub const Connection = struct {
    ptr: ?*c.turso_connection_t,
    allocator: std.mem.Allocator,
    extra_io: ?statement_mod.Statement.ExtraIo = null,

    /// Set busy timeout in milliseconds for the connection.
    pub fn setBusyTimeout(self: *Connection, timeout_ms: i64) err.TursoError!void {
        if (self.ptr == null) return err.mapStatus(c.TURSO_MISUSE, null, self.allocator);
        c.turso_connection_set_busy_timeout_ms(self.ptr.?, timeout_ms);
    }

    /// Checked autocommit accessor. Invalid connection handles return `error.Misuse`.
    pub fn getAutocommitChecked(self: *Connection) err.TursoError!bool {
        if (self.ptr == null) return err.mapStatus(c.TURSO_MISUSE, null, self.allocator);
        return c.turso_connection_get_autocommit(self.ptr.?);
    }

    /// Get autocommit state of the connection.
    /// Convenience wrapper: invalid handles return false. Use `getAutocommitChecked` when misuse must be reported.
    pub fn getAutocommit(self: *Connection) bool {
        return self.getAutocommitChecked() catch false;
    }

    /// Checked last-insert-rowid accessor. Invalid connection handles return `error.Misuse`.
    pub fn lastInsertRowIdChecked(self: *Connection) err.TursoError!i64 {
        if (self.ptr == null) return err.mapStatus(c.TURSO_MISUSE, null, self.allocator);
        return c.turso_connection_last_insert_rowid(self.ptr.?);
    }

    /// Get last insert rowid for the connection, or 0 if no inserts happened.
    /// Convenience wrapper: invalid handles return 0. Use `lastInsertRowIdChecked` when misuse must be reported.
    pub fn lastInsertRowId(self: *Connection) i64 {
        return self.lastInsertRowIdChecked() catch 0;
    }

    /// Close the connection for further operations. Returns TursoError on failure.
    pub fn close(self: *Connection) err.TursoError!void {
        if (self.ptr == null) return err.mapStatus(c.TURSO_MISUSE, null, self.allocator);
        var err_ptr: [*c]const u8 = null;
        const status_code = c.turso_connection_close(self.ptr.?, &err_ptr);
        if (status_code != c.TURSO_OK) {
            return err.mapStatus(status_code, err_ptr, self.allocator);
        }
    }

    /// Prepare a single SQL statement and return a value handle.
    pub fn prepareSingle(self: *Connection, sql: anytype) err.TursoError!statement_mod.Statement {
        if (comptime isZeroTerminatedString(@TypeOf(sql))) {
            const sql_z: [:0]const u8 = sql;
            return self.prepareSingleInternalZ(sql_z, null);
        }
        const sql_slice: []const u8 = sql;
        return self.prepareSingleInternal(sql_slice, null);
    }

    /// Prepare a zero-terminated SQL statement without allocating a temporary C string.
    pub fn prepareSingleZ(self: *Connection, sql: [:0]const u8) err.TursoError!statement_mod.Statement {
        return self.prepareSingleInternalZ(sql, null);
    }

    /// Prepare a single SQL statement and capture engine diagnostics on failure.
    pub fn prepareSingleWithDiagnostic(
        self: *Connection,
        sql: anytype,
        diagnostic: *err.Diagnostic,
    ) err.TursoError!statement_mod.Statement {
        if (comptime isZeroTerminatedString(@TypeOf(sql))) {
            const sql_z: [:0]const u8 = sql;
            return self.prepareSingleInternalZ(sql_z, diagnostic);
        }
        const sql_slice: []const u8 = sql;
        return self.prepareSingleInternal(sql_slice, diagnostic);
    }

    /// Prepare a zero-terminated SQL statement and capture engine diagnostics on failure.
    pub fn prepareSingleZWithDiagnostic(
        self: *Connection,
        sql: [:0]const u8,
        diagnostic: *err.Diagnostic,
    ) err.TursoError!statement_mod.Statement {
        return self.prepareSingleInternalZ(sql, diagnostic);
    }

    fn prepareSingleInternal(
        self: *Connection,
        sql: []const u8,
        diagnostic: ?*err.Diagnostic,
    ) err.TursoError!statement_mod.Statement {
        const c_sql = try self.allocator.dupeZ(u8, sql);
        defer self.allocator.free(c_sql);
        return self.prepareSingleInternalZ(c_sql, diagnostic);
    }

    fn prepareSingleInternalZ(
        self: *Connection,
        sql: [:0]const u8,
        diagnostic: ?*err.Diagnostic,
    ) err.TursoError!statement_mod.Statement {
        if (self.ptr == null) {
            return err.mapStatus(
                c.TURSO_MISUSE,
                null,
                self.allocator,
            );
        }

        var stmt: ?*c.turso_statement_t = null;
        var err_ptr: [*c]const u8 = null;
        const status_code = c.turso_connection_prepare_single(self.ptr.?, sql, &stmt, &err_ptr);

        if (status_code != c.TURSO_OK) {
            return err.mapStatusWithDiagnostic(status_code, err_ptr, self.allocator, diagnostic);
        }

        return statement_mod.Statement{
            .ptr = stmt,
            .allocator = self.allocator,
            .extra_io = self.extra_io,
        };
    }

    /// Prepare and execute a single SQL statement to completion.
    pub fn execute(self: *Connection, sql: anytype) err.TursoError!u64 {
        var stmt = try self.prepareSingle(sql);
        defer {
            stmt.finalize() catch {};
            stmt.deinit();
        }
        return stmt.execute(.{});
    }

    /// Prepare and execute a zero-terminated SQL statement without allocating
    /// a temporary C string for the SQL text.
    pub fn executeZ(self: *Connection, sql: [:0]const u8) err.TursoError!u64 {
        var stmt = try self.prepareSingleZ(sql);
        defer {
            stmt.finalize() catch {};
            stmt.deinit();
        }
        return stmt.execute(.{});
    }

    /// Prepare and execute SQL while capturing engine diagnostics on failure.
    pub fn executeWithDiagnostic(
        self: *Connection,
        sql: anytype,
        diagnostic: *err.Diagnostic,
    ) err.TursoError!u64 {
        var stmt = try self.prepareSingleWithDiagnostic(sql, diagnostic);
        defer {
            stmt.finalize() catch {};
            stmt.deinit();
        }
        return stmt.executeWithDiagnostic(diagnostic);
    }

    /// Execute every statement in a SQL batch and return the total row-change count.
    pub fn executeBatch(self: *Connection, sql: []const u8) err.TursoError!u64 {
        var start: usize = 0;
        var total_changes: u64 = 0;

        while (start < sql.len) {
            const result = try self.prepareFirst(sql[start..]);
            if (result.statement == null) {
                if (std.mem.trim(u8, sql[start..], " \t\r\n").len != 0) {
                    return err.mapStatus(c.TURSO_MISUSE, null, self.allocator);
                }
                break;
            }

            if (result.tail_idx == 0) {
                return err.mapStatus(c.TURSO_MISUSE, null, self.allocator);
            }

            var stmt = result.statement.?;
            defer {
                stmt.finalize() catch {};
                stmt.deinit();
            }

            total_changes += try stmt.execute(.{});
            start += result.tail_idx;
        }

        return total_changes;
    }

    /// Prepare, run, and collect a query into owned Zig rows.
    pub fn query(self: *Connection, sql: anytype) err.TursoError!QueryResult {
        var stream = try self.rows(sql);
        defer stream.deinit();

        const column_count = stream.column_count;

        var columns = try self.allocator.alloc(Column, column_count);
        var initialized_columns: usize = 0;
        errdefer {
            for (columns[0..initialized_columns]) |*column| {
                column.deinit(self.allocator);
            }
            self.allocator.free(columns);
        }

        for (columns, 0..) |*column, index| {
            const name = try stream.stmt.columnName(index);
            const decltype = stream.stmt.columnDecltype(index) catch |column_err| {
                self.allocator.free(name);
                return column_err;
            };
            column.* = .{
                .name = name,
                .decltype = decltype,
            };
            initialized_columns += 1;
        }

        var row_list = std.array_list.Managed(Row).init(self.allocator);
        errdefer {
            for (row_list.items) |*row| {
                row.deinit(self.allocator);
            }
            row_list.deinit();
        }

        while (try stream.next()) |row| {
            var values = try self.allocator.alloc(value_mod.OwnedValue, column_count);
            var initialized_values: usize = 0;
            errdefer {
                for (values[0..initialized_values]) |*value| {
                    value.deinit(self.allocator);
                }
                self.allocator.free(values);
            }

            for (values, 0..) |*value, index| {
                value.* = try row.ownedValue(index);
                initialized_values += 1;
            }

            try row_list.append(.{ .values = values });
        }

        return .{
            .columns = columns,
            .rows = try row_list.toOwnedSlice(),
            .allocator = self.allocator,
        };
    }

    /// Prepare a query for streaming row iteration.
    /// Borrowed text/blob slices from `RowView` stay valid until `Rows.next()`,
    /// `Statement.reset()`, `Statement.finalize()`, or `Rows.deinit()`.
    pub fn rows(self: *Connection, sql: anytype) err.TursoError!Rows {
        var stmt = try self.prepareSingle(sql);
        errdefer {
            stmt.finalize() catch {};
            stmt.deinit();
        }

        const raw_column_count = try stmt.columnCountChecked();
        if (raw_column_count < 0) {
            return err.mapStatus(c.TURSO_MISUSE, null, self.allocator);
        }

        return .{
            .stmt = stmt,
            .column_count = @intCast(raw_column_count),
        };
    }

    pub fn transaction(self: *Connection) err.TursoError!Transaction {
        _ = try self.execute("BEGIN");
        return .{ .conn = self };
    }

    /// Prepare the first SQL statement from a string that may contain multiple statements.
    /// Returns null statement if no statements could be parsed, or TursoError on failure.
    pub fn prepareFirst(self: *Connection, sql: []const u8) err.TursoError!PrepareFirstResult {
        if (self.ptr == null) {
            return err.mapStatus(
                c.TURSO_MISUSE,
                null,
                self.allocator,
            );
        }

        const c_sql = try self.allocator.dupeZ(u8, sql);
        defer self.allocator.free(c_sql);

        var stmt: ?*c.turso_statement_t = null;
        var tail_idx: usize = 0;
        var err_ptr: [*c]const u8 = null;
        const status_code = c.turso_connection_prepare_first(self.ptr.?, c_sql, &stmt, &tail_idx, &err_ptr);

        if (status_code != c.TURSO_OK) {
            return err.mapStatus(status_code, err_ptr, self.allocator);
        }

        var wrapped_stmt: ?statement_mod.Statement = null;
        if (stmt) |s| {
            wrapped_stmt = statement_mod.Statement{
                .ptr = s,
                .allocator = self.allocator,
                .extra_io = self.extra_io,
            };
        }

        return PrepareFirstResult{
            .statement = wrapped_stmt,
            .tail_idx = tail_idx,
        };
    }

    /// Deinitialize and free the connection handle.
    pub fn deinit(self: *Connection) void {
        if (self.ptr) |p| {
            c.turso_connection_deinit(p);
        }
        self.ptr = null;
    }
};

fn isZeroTerminatedString(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |ptr| switch (ptr.size) {
            .slice, .many => ptr.child == u8 and ptr.sentinel() != null and ptr.sentinel().? == 0,
            .one => switch (@typeInfo(ptr.child)) {
                .array => |array| array.child == u8 and array.sentinel() != null and array.sentinel().? == 0,
                else => false,
            },
            else => false,
        },
        .array => |array| array.child == u8 and array.sentinel() != null and array.sentinel().? == 0,
        else => false,
    };
}
