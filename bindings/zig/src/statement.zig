const std = @import("std");
const c = @import("c.zig");
const err = @import("error.zig");
const status = @import("status.zig");
const value_mod = @import("value.zig");

/// Wrapper around `turso_statement_t` with Zig-friendly lifecycle management.
pub const Statement = struct {
    ptr: ?*c.turso_statement_t,
    allocator: std.mem.Allocator,

    /// Execute a single statement to completion. Returns row changes count or TursoError.
    pub fn execute(self: *Statement) err.TursoError!u64 {
        return self.executeSync();
    }

    /// Step statement execution once. Returns TURSO_ROW if a row is available, TURSO_DONE when finished, or TursoError.
    pub fn step(self: *Statement) err.TursoError!status.StatusCode {
        return self.stepSync();
    }

    /// Execute one iteration of the underlying IO backend after TURSO_IO status. Returns TursoError on failure.
    pub fn runIO(self: *Statement) err.TursoError!void {
        if (self.ptr == null) return;
        var err_ptr: [*c]const u8 = null;
        const status_code = c.turso_statement_run_io(self.ptr.?, &err_ptr);
        if (status_code != c.TURSO_OK) {
            return err.mapStatus(status_code, err_ptr, self.allocator);
        }
    }

    /// Reset a statement to prepare it for re-execution. Returns TursoError on failure.
    pub fn reset(self: *Statement) err.TursoError!void {
        if (self.ptr == null) return;
        var err_ptr: [*c]const u8 = null;
        const status_code = c.turso_statement_reset(self.ptr.?, &err_ptr);
        if (status_code != c.TURSO_OK) {
            return err.mapStatus(status_code, err_ptr, self.allocator);
        }
    }

    /// Finalize a statement to complete execution and cleanup. Returns TursoError on failure.
    pub fn finalize(self: *Statement) err.TursoError!void {
        if (self.ptr == null) return;
        var err_ptr: [*c]const u8 = null;
        const status_code = c.turso_statement_finalize(self.ptr.?, &err_ptr);
        return switch (@as(status.StatusCode, @enumFromInt(status_code))) {
            .TURSO_OK, .TURSO_DONE => {},
            else => err.mapStatus(status_code, err_ptr, self.allocator),
        };
    }

    /// Bind a NULL value to a positional parameter (1-indexed). Returns TursoError on failure.
    pub fn bindNull(self: *Statement, position: usize) err.TursoError!void {
        if (self.ptr == null) return;
        const status_code = c.turso_statement_bind_positional_null(self.ptr.?, position);
        if (status_code != c.TURSO_OK) {
            return err.mapStatus(status_code, null, self.allocator);
        }
    }

    /// Bind an INTEGER value to a positional parameter (1-indexed). Returns TursoError on failure.
    pub fn bindInt(self: *Statement, position: usize, value: i64) err.TursoError!void {
        if (self.ptr == null) return;
        const status_code = c.turso_statement_bind_positional_int(self.ptr.?, position, value);
        if (status_code != c.TURSO_OK) {
            return err.mapStatus(status_code, null, self.allocator);
        }
    }

    /// Bind a DOUBLE value to a positional parameter (1-indexed). Returns TursoError on failure.
    pub fn bindDouble(self: *Statement, position: usize, value: f64) err.TursoError!void {
        if (self.ptr == null) return;
        const status_code = c.turso_statement_bind_positional_double(self.ptr.?, position, value);
        if (status_code != c.TURSO_OK) {
            return err.mapStatus(status_code, null, self.allocator);
        }
    }

    /// Bind a TEXT value to a positional parameter (1-indexed). Returns TursoError on failure.
    pub fn bindText(self: *Statement, position: usize, value: []const u8) err.TursoError!void {
        if (self.ptr == null) return;
        var ptr: [*]const u8 = "";
        if (value.len > 0) {
            ptr = value.ptr;
        }
        const status_code = c.turso_statement_bind_positional_text(self.ptr.?, position, ptr, value.len);
        if (status_code != c.TURSO_OK) {
            return err.mapStatus(status_code, null, self.allocator);
        }
    }

    /// Bind a BLOB value to a positional parameter (1-indexed). Returns TursoError on failure.
    pub fn bindBlob(self: *Statement, position: usize, value: []const u8) err.TursoError!void {
        if (self.ptr == null) return;
        var ptr: [*]const u8 = "";
        if (value.len > 0) {
            ptr = value.ptr;
        }
        const status_code = c.turso_statement_bind_positional_blob(self.ptr.?, position, ptr, value.len);
        if (status_code != c.TURSO_OK) {
            return err.mapStatus(status_code, null, self.allocator);
        }
    }

    /// Get the value kind at the given column index for the current row.
    pub fn rowValueKind(self: *Statement, index: usize) value_mod.ValueKind {
        if (self.ptr == null) return .unknown;
        const kind = c.turso_statement_row_value_kind(self.ptr.?, index);
        return value_mod.ValueKind.fromC(@enumFromInt(kind));
    }

    /// Get an INTEGER value at the given column index. Returns 0 for non-integer kinds.
    pub fn rowValueInt(self: *Statement, index: usize) i64 {
        if (self.ptr == null) return 0;
        return c.turso_statement_row_value_int(self.ptr.?, index);
    }

    /// Get a REAL value at the given column index. Returns 0 for non-real kinds.
    pub fn rowValueDouble(self: *Statement, index: usize) f64 {
        if (self.ptr == null) return 0;
        return c.turso_statement_row_value_double(self.ptr.?, index);
    }

    /// Get a TEXT value at the given column index as an owned copy. Returns empty string for non-text kinds.
    pub fn rowValueText(self: *Statement, index: usize) ![]u8 {
        if (self.ptr == null) return self.allocator.dupe(u8, "");
        return value_mod.readText(self.ptr.?, index, self.allocator);
    }

    /// Get a BLOB value at the given column index as an owned copy. Returns empty slice for non-blob kinds.
    pub fn rowValueBlob(self: *Statement, index: usize) ![]u8 {
        if (self.ptr == null) return try self.allocator.dupe(u8, "");
        return value_mod.readBlob(self.ptr.?, index, self.allocator);
    }

    /// Get the value at the given column index as an owned Zig value.
    pub fn rowValue(self: *Statement, index: usize) !value_mod.OwnedValue {
        return switch (self.rowValueKind(index)) {
            .integer => .{ .integer = self.rowValueInt(index) },
            .real => .{ .real = self.rowValueDouble(index) },
            .text => .{ .text = try self.rowValueText(index) },
            .blob => .{ .blob = try self.rowValueBlob(index) },
            .null => .{ .null = {} },
            .unknown => .{ .unknown = {} },
        };
    }

    /// Get the column count for the prepared statement.
    pub fn columnCount(self: *Statement) i64 {
        if (self.ptr == null) return 0;
        return c.turso_statement_column_count(self.ptr.?);
    }

    /// Get the column name at the given index. The returned string is an owned copy allocated with self.allocator; the C-allocated Turso string is freed via turso_str_deinit.
    pub fn columnName(self: *Statement, index: usize) ![]u8 {
        if (self.ptr == null) return self.allocator.dupe(u8, "");
        const ptr = c.turso_statement_column_name(self.ptr.?, index);
        defer if (ptr) |p| c.turso_str_deinit(p);
        if (ptr) |p| return try self.allocator.dupe(u8, std.mem.span(p));
        return self.allocator.dupe(u8, "");
    }

    /// Get the declared column type at the given index (e.g. "INTEGER", "TEXT"). Returns empty string for non-available types. The C-allocated Turso string is freed via turso_str_deinit.
    pub fn columnDecltype(self: *Statement, index: usize) ![]u8 {
        if (self.ptr == null) return self.allocator.dupe(u8, "");
        const ptr = c.turso_statement_column_decltype(self.ptr.?, index);
        defer if (ptr) |p| c.turso_str_deinit(p);
        if (ptr) |p| return try self.allocator.dupe(u8, std.mem.span(p));
        return self.allocator.dupe(u8, "");
    }

    /// Resolve a named parameter to its 1-indexed positional value. Returns -1 if the name is not found.
    pub fn namedPosition(self: *Statement, name: []const u8) i64 {
        if (self.ptr == null) return -1;
        const c_name = self.allocator.dupeZ(u8, name) catch return -1;
        defer self.allocator.free(c_name);
        return c.turso_statement_named_position(self.ptr.?, c_name);
    }

    /// Get the total number of parameters for the prepared statement. Returns -1 if the pointer is invalid.
    pub fn parametersCount(self: *Statement) i64 {
        if (self.ptr == null) return -1;
        return c.turso_statement_parameters_count(self.ptr.?);
    }

    /// Execute a single statement to completion, handling TURSO_IO by calling runIO and retrying. Returns row changes count or TursoError.
    fn executeSync(self: *Statement) err.TursoError!u64 {
        if (self.ptr == null) {
            return err.mapStatus(
                c.TURSO_MISUSE,
                null,
                self.allocator,
            );
        }
        while (true) {
            var changes: u64 = 0;
            var err_ptr: [*c]const u8 = null;
            const status_code = c.turso_statement_execute(self.ptr.?, &changes, &err_ptr);
            return switch (@as(status.StatusCode, @enumFromInt(status_code))) {
                .TURSO_OK, .TURSO_DONE => changes,
                .TURSO_IO => {
                    try self.runIO();
                    continue;
                },
                else => err.mapStatus(status_code, err_ptr, self.allocator),
            };
        }
    }

    /// Step statement execution to completion, handling TURSO_IO by calling runIO and retrying. Returns final status (TURSO_ROW or TURSO_DONE) or TursoError.
    fn stepSync(self: *Statement) err.TursoError!status.StatusCode {
        if (self.ptr == null) {
            return err.mapStatus(
                c.TURSO_MISUSE,
                null,
                self.allocator,
            );
        }
        while (true) {
            var err_ptr: [*c]const u8 = null;
            const status_code = c.turso_statement_step(self.ptr.?, &err_ptr);
            return switch (@as(status.StatusCode, @enumFromInt(status_code))) {
                .TURSO_ROW, .TURSO_DONE => @enumFromInt(status_code),
                .TURSO_IO => {
                    try self.runIO();
                    continue;
                },
                else => err.mapStatus(status_code, err_ptr, self.allocator),
            };
        }
    }

    /// Get the number of row modifications made by the most recent executed statement.
    pub fn nChange(self: *Statement) i64 {
        if (self.ptr) |p| {
            return c.turso_statement_n_change(p);
        }
        return 0;
    }

    /// Deinitialize and free the statement handle.
    pub fn deinit(self: *Statement) void {
        if (self.ptr) |p| {
            c.turso_statement_deinit(p);
        }
        self.ptr = null;
    }
};
