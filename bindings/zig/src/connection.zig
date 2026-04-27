const std = @import("std");
const c = @import("c.zig");
const err = @import("error.zig");
const statement_mod = @import("statement.zig");
const value_mod = @import("value.zig");

/// Result of preparing the first statement from multi-statement SQL.
pub const PrepareFirstResult = struct {
    /// The prepared statement, or null if no statements could be parsed.
    statement: ?*statement_mod.Statement,
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

    pub fn execute(self: *Transaction, sql: []const u8) err.TursoError!u64 {
        return self.conn.execute(sql);
    }

    pub fn query(self: *Transaction, sql: []const u8) err.TursoError!QueryResult {
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

    /// Prepare a single SQL statement. Returns an owned Statement or TursoError.
    pub fn prepareSingle(self: *Connection, sql: []const u8) err.TursoError!*statement_mod.Statement {
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
        var err_ptr: [*c]const u8 = null;
        const status_code = c.turso_connection_prepare_single(self.ptr.?, c_sql, &stmt, &err_ptr);

        if (status_code != c.TURSO_OK) {
            return err.mapStatus(status_code, err_ptr, self.allocator);
        }

        const statement_wrapper = self.allocator.create(statement_mod.Statement) catch {
            var finalize_err: [*c]const u8 = null;
            _ = c.turso_statement_finalize(stmt, &finalize_err);
            if (finalize_err != null) {
                c.turso_str_deinit(finalize_err);
            }
            c.turso_statement_deinit(stmt);
            return error.OutOfMemory;
        };
        statement_wrapper.* = statement_mod.Statement{
            .ptr = stmt,
            .allocator = self.allocator,
        };
        return statement_wrapper;
    }

    /// Prepare and execute a single SQL statement to completion.
    pub fn execute(self: *Connection, sql: []const u8) err.TursoError!u64 {
        const stmt = try self.prepareSingle(sql);
        defer {
            stmt.finalize() catch {};
            stmt.deinit();
            self.allocator.destroy(stmt);
        }
        return stmt.execute();
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

            const stmt = result.statement.?;
            defer {
                stmt.finalize() catch {};
                stmt.deinit();
                self.allocator.destroy(stmt);
            }

            total_changes += try stmt.execute();
            start += result.tail_idx;
        }

        return total_changes;
    }

    /// Prepare, run, and collect a query into owned Zig rows.
    pub fn query(self: *Connection, sql: []const u8) err.TursoError!QueryResult {
        const stmt = try self.prepareSingle(sql);
        defer {
            stmt.finalize() catch {};
            stmt.deinit();
            self.allocator.destroy(stmt);
        }

        const raw_column_count = try stmt.columnCountChecked();
        if (raw_column_count < 0) {
            return err.mapStatus(c.TURSO_MISUSE, null, self.allocator);
        }
        const column_count: usize = @intCast(raw_column_count);

        var columns = try self.allocator.alloc(Column, column_count);
        var initialized_columns: usize = 0;
        errdefer {
            for (columns[0..initialized_columns]) |*column| {
                column.deinit(self.allocator);
            }
            self.allocator.free(columns);
        }

        for (columns, 0..) |*column, index| {
            const name = try stmt.columnName(index);
            const decltype = stmt.columnDecltype(index) catch |column_err| {
                self.allocator.free(name);
                return column_err;
            };
            column.* = .{
                .name = name,
                .decltype = decltype,
            };
            initialized_columns += 1;
        }

        var rows = std.array_list.Managed(Row).init(self.allocator);
        errdefer {
            for (rows.items) |*row| {
                row.deinit(self.allocator);
            }
            rows.deinit();
        }

        while (true) {
            switch (try stmt.step()) {
                .TURSO_ROW => {
                    var values = try self.allocator.alloc(value_mod.OwnedValue, column_count);
                    var initialized_values: usize = 0;
                    errdefer {
                        for (values[0..initialized_values]) |*value| {
                            value.deinit(self.allocator);
                        }
                        self.allocator.free(values);
                    }

                    for (values, 0..) |*value, index| {
                        value.* = try stmt.rowValue(index);
                        initialized_values += 1;
                    }

                    try rows.append(.{ .values = values });
                },
                .TURSO_DONE => break,
                else => return err.mapStatus(c.TURSO_MISUSE, null, self.allocator),
            }
        }

        return .{
            .columns = columns,
            .rows = try rows.toOwnedSlice(),
            .allocator = self.allocator,
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

        var wrapped_stmt: ?*statement_mod.Statement = null;
        if (stmt) |s| {
            const statement_wrapper = self.allocator.create(statement_mod.Statement) catch {
                var finalize_err: [*c]const u8 = null;
                _ = c.turso_statement_finalize(s, &finalize_err);
                if (finalize_err != null) {
                    c.turso_str_deinit(finalize_err);
                }
                c.turso_statement_deinit(s);
                return error.OutOfMemory;
            };
            statement_wrapper.* = statement_mod.Statement{
                .ptr = s,
                .allocator = self.allocator,
            };
            wrapped_stmt = statement_wrapper;
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
