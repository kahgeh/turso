const std = @import("std");
const c = @import("c.zig");
const err = @import("error.zig");

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
        const status = c.turso_connection_close(self.ptr.?, &err_ptr);
        if (status != @intFromEnum(c.turso_status_code_t.TURSO_OK)) {
            return err.mapStatus(status, err_ptr, self.allocator);
        }
    }

    /// Deinitialize and free the connection handle.
    pub fn deinit(self: *Connection) void {
        if (self.ptr) |p| {
            c.turso_connection_deinit(p);
        }
        self.ptr = null;
    }
};
