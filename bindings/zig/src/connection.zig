const std = @import("std");
const c = @import("c.zig");
const err = @import("error.zig");
const statement_mod = @import("statement.zig");

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
        var err_ptr: [*:0]const u8 = null;
        const status_code = c.turso_connection_close(self.ptr.?, &err_ptr);
        if (status_code != @intFromEnum(c.turso_status_code_t.TURSO_OK)) {
            return err.mapStatus(status_code, err_ptr, self.allocator);
        }
    }

    /// Prepare a single SQL statement. Returns an owned Statement or TursoError.
    pub fn prepareSingle(self: *Connection, sql: []const u8) err.TursoError!*statement_mod.Statement {
        if (self.ptr == null) {
            return err.mapStatus(
                @intFromEnum(c.turso_status_code_t.TURSO_MISUSE),
                null,
                self.allocator,
            );
        }

        var stmt: ?*c.turso_statement_t = null;
        var err_ptr: [*:0]const u8 = null;
        const status_code = c.turso_connection_prepare_single(self.ptr.?, sql, &stmt, &err_ptr);

        if (status_code != @intFromEnum(c.turso_status_code_t.TURSO_OK)) {
            return err.mapStatus(status_code, err_ptr, self.allocator);
        }

        const statement_wrapper = self.allocator.create(statement_mod.Statement) catch |e| {
            var finalize_err: [*:0]const u8 = null;
            _ = c.turso_statement_finalize(stmt, &finalize_err);
            if (finalize_err) |p| {
                c.turso_str_deinit(p);
            }
            c.turso_statement_deinit(stmt);
            var msg_buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&msg_buf, "failed to allocate Statement: {}", .{e}) catch "failed to allocate Statement";
            return err.TursoError{
                .code = @enumFromInt(@intFromEnum(c.turso_status_code_t.TURSO_ERROR)),
                .allocator = self.allocator,
                .owned_message = try self.allocator.dupe(u8, msg),
            };
        };
        statement_wrapper.* = statement_mod.Statement{
            .ptr = stmt,
            .allocator = self.allocator,
        };
        return statement_wrapper;
    }

    /// Deinitialize and free the connection handle.
    pub fn deinit(self: *Connection) void {
        if (self.ptr) |p| {
            c.turso_connection_deinit(p);
        }
        self.ptr = null;
    }
};
