const std = @import("std");
const c = @import("c.zig");
const err = @import("error.zig");
const statement_mod = @import("statement.zig");

/// Result of preparing the first statement from multi-statement SQL.
pub const PrepareFirstResult = struct {
    /// The prepared statement, or null if no statements could be parsed.
    statement: ?*statement_mod.Statement,
    /// Byte offset in sql right after the parsed statement.
    tail_idx: usize,
};

/// Wrapper around `turso_connection_t` with Zig-friendly lifecycle management.
pub const Connection = struct {
    ptr: ?*c.turso_connection_t,
    allocator: std.mem.Allocator,

    /// Set busy timeout in milliseconds for the connection.
    pub fn setBusyTimeout(self: *Connection, timeout_ms: i64) void {
        if (self.ptr) |p| {
            c.turso_connection_set_busy_timeout_ms(p, timeout_ms);
        }
    }

    /// Get autocommit state of the connection.
    pub fn getAutocommit(self: *Connection) bool {
        if (self.ptr) |p| {
            return c.turso_connection_get_autocommit(p);
        }
        return false;
    }

    /// Get last insert rowid for the connection, or 0 if no inserts happened.
    pub fn lastInsertRowId(self: *Connection) i64 {
        if (self.ptr) |p| {
            return c.turso_connection_last_insert_rowid(p);
        }
        return 0;
    }

    /// Close the connection for further operations. Returns TursoError on failure.
    pub fn close(self: *Connection) err.TursoError!void {
        if (self.ptr == null) return;
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
