const std = @import("std");
const c = @import("c.zig");
const err = @import("error.zig");
const status = @import("status.zig");
const value_mod = @import("value.zig");

/// Wrapper around `turso_statement_t` with Zig-friendly lifecycle management.
pub const Statement = struct {
    ptr: ?*c.turso_statement_t,
    allocator: std.mem.Allocator,
    extra_io: ?ExtraIo = null,

    pub const ExtraIo = struct {
        context: *anyopaque,
        run: *const fn (context: *anyopaque) err.TursoError!void,
    };

    pub const ExecuteResult = struct {
        status_code: status.StatusCode,
        changes: u64,
    };

    /// Execute a single statement to completion. If positional parameters are
    /// provided as a tuple, the statement is reset and parameters are rebound
    /// before execution. Pass `.{}` to execute with existing bindings.
    pub fn execute(self: *Statement, params: anytype) err.TursoError!u64 {
        if (try self.bindExecuteParams(params)) {
            try self.reset();
            try self.bindParams(params);
        }
        return self.executeSync(null);
    }

    /// Execute a single statement to completion and capture engine diagnostics on failure.
    pub fn executeWithDiagnostic(self: *Statement, diagnostic: *err.Diagnostic) err.TursoError!u64 {
        return self.executeSync(diagnostic);
    }

    /// Step statement execution once. Returns TURSO_ROW if a row is available, TURSO_DONE when finished, or TursoError.
    pub fn step(self: *Statement) err.TursoError!status.StatusCode {
        return self.stepSync();
    }

    /// Execute one C API call without auto-driving `TURSO_IO`.
    pub fn executeOnce(self: *Statement) err.TursoError!ExecuteResult {
        return self.executeOnceWithDiagnostic(null);
    }

    /// Step one C API call without auto-driving `TURSO_IO`.
    pub fn stepOnce(self: *Statement) err.TursoError!status.StatusCode {
        if (self.ptr == null) {
            return err.mapStatus(
                c.TURSO_MISUSE,
                null,
                self.allocator,
            );
        }

        var err_ptr: [*c]const u8 = null;
        const status_code = c.turso_statement_step(self.ptr.?, &err_ptr);
        return switch (@as(status.StatusCode, @enumFromInt(status_code))) {
            .TURSO_ROW, .TURSO_DONE, .TURSO_IO => @enumFromInt(status_code),
            else => err.mapStatus(status_code, err_ptr, self.allocator),
        };
    }

    /// Execute one iteration of the underlying IO backend after TURSO_IO status. Returns TursoError on failure.
    pub fn runIO(self: *Statement) err.TursoError!void {
        if (self.ptr == null) return err.mapStatus(c.TURSO_MISUSE, null, self.allocator);
        var err_ptr: [*c]const u8 = null;
        const status_code = c.turso_statement_run_io(self.ptr.?, &err_ptr);
        if (status_code != c.TURSO_OK) {
            return err.mapStatus(status_code, err_ptr, self.allocator);
        }
        if (self.extra_io) |extra_io| {
            try extra_io.run(extra_io.context);
        }
    }

    /// Reset a statement to prepare it for re-execution. Returns TursoError on failure.
    pub fn reset(self: *Statement) err.TursoError!void {
        if (self.ptr == null) return err.mapStatus(c.TURSO_MISUSE, null, self.allocator);
        var err_ptr: [*c]const u8 = null;
        const status_code = c.turso_statement_reset(self.ptr.?, &err_ptr);
        if (status_code != c.TURSO_OK) {
            return err.mapStatus(status_code, err_ptr, self.allocator);
        }
    }

    /// Finalize a statement to complete execution and cleanup. Returns TursoError on failure.
    pub fn finalize(self: *Statement) err.TursoError!void {
        if (self.ptr == null) return err.mapStatus(c.TURSO_MISUSE, null, self.allocator);
        var err_ptr: [*c]const u8 = null;
        const status_code = c.turso_statement_finalize(self.ptr.?, &err_ptr);
        return switch (@as(status.StatusCode, @enumFromInt(status_code))) {
            .TURSO_OK, .TURSO_DONE => {},
            else => err.mapStatus(status_code, err_ptr, self.allocator),
        };
    }

    /// Bind a NULL value to a positional parameter (1-indexed). Returns TursoError on failure.
    pub fn bindNull(self: *Statement, position: usize) err.TursoError!void {
        if (self.ptr == null) return err.mapStatus(c.TURSO_MISUSE, null, self.allocator);
        const status_code = c.turso_statement_bind_positional_null(self.ptr.?, position);
        if (status_code != c.TURSO_OK) {
            return err.mapStatus(status_code, null, self.allocator);
        }
    }

    /// Bind an INTEGER value to a positional parameter (1-indexed). Returns TursoError on failure.
    pub fn bindInt(self: *Statement, position: usize, value: i64) err.TursoError!void {
        if (self.ptr == null) return err.mapStatus(c.TURSO_MISUSE, null, self.allocator);
        const status_code = c.turso_statement_bind_positional_int(self.ptr.?, position, value);
        if (status_code != c.TURSO_OK) {
            return err.mapStatus(status_code, null, self.allocator);
        }
    }

    /// Bind a DOUBLE value to a positional parameter (1-indexed). Returns TursoError on failure.
    pub fn bindDouble(self: *Statement, position: usize, value: f64) err.TursoError!void {
        if (self.ptr == null) return err.mapStatus(c.TURSO_MISUSE, null, self.allocator);
        const status_code = c.turso_statement_bind_positional_double(self.ptr.?, position, value);
        if (status_code != c.TURSO_OK) {
            return err.mapStatus(status_code, null, self.allocator);
        }
    }

    /// Bind a TEXT value to a positional parameter (1-indexed). String literals
    /// use a borrowed static bind; runtime slices are copied for safety.
    pub fn bindText(self: *Statement, position: usize, value: anytype) err.TursoError!void {
        if (comptime isStaticText(@TypeOf(value))) {
            const text: []const u8 = value;
            return self.bindTextStaticInternal(position, text);
        }

        const text: []const u8 = value;
        return self.bindTextOwned(position, text);
    }

    fn bindTextOwned(self: *Statement, position: usize, value: []const u8) err.TursoError!void {
        if (self.ptr == null) return err.mapStatus(c.TURSO_MISUSE, null, self.allocator);
        const ptr = if (value.len > 0) value.ptr else "";
        const status_code = c.turso_statement_bind_positional_text(self.ptr.?, position, ptr, value.len);
        if (status_code != c.TURSO_OK) {
            return err.mapStatus(status_code, null, self.allocator);
        }
    }

    fn bindTextStaticInternal(self: *Statement, position: usize, value: []const u8) err.TursoError!void {
        if (self.ptr == null) return err.mapStatus(c.TURSO_MISUSE, null, self.allocator);
        const status_code = c.turso_statement_bind_positional_text_static(self.ptr.?, position, value.ptr, value.len);
        if (status_code != c.TURSO_OK) {
            return err.mapStatus(status_code, null, self.allocator);
        }
    }

    fn bindExecuteParams(self: *Statement, params: anytype) err.TursoError!bool {
        _ = self;
        const T = @TypeOf(params);
        return switch (@typeInfo(T)) {
            .@"struct" => |info| blk: {
                if (!info.is_tuple) @compileError("execute params must be a tuple, e.g. .{ id, \"value\" }");
                break :blk info.fields.len != 0;
            },
            else => @compileError("execute params must be a tuple, e.g. .{} or .{ id, \"value\" }"),
        };
    }

    fn bindParams(self: *Statement, params: anytype) err.TursoError!void {
        const T = @TypeOf(params);
        switch (@typeInfo(T)) {
            .@"struct" => |info| {
                if (!info.is_tuple) @compileError("execute params must be a tuple");
                inline for (info.fields, 0..) |field, index| {
                    try self.bindValue(index + 1, @field(params, field.name));
                }
            },
            else => @compileError("execute params must be a tuple"),
        }
    }

    fn bindValue(self: *Statement, position: usize, value: anytype) err.TursoError!void {
        const T = @TypeOf(value);
        switch (@typeInfo(T)) {
            .null => try self.bindNull(position),
            .bool => try self.bindInt(position, if (value) 1 else 0),
            .int, .comptime_int => try self.bindInt(position, @intCast(value)),
            .float, .comptime_float => try self.bindDouble(position, @floatCast(value)),
            .optional => {
                if (value) |unwrapped| {
                    try self.bindValue(position, unwrapped);
                } else {
                    try self.bindNull(position);
                }
            },
            .pointer => |ptr| switch (ptr.size) {
                .slice, .many => {
                    if (ptr.child != u8) @compileError("only []u8/[]const u8 slices are supported as text params");
                    try self.bindText(position, value);
                },
                .one => switch (@typeInfo(ptr.child)) {
                    .array => |array| {
                        if (array.child != u8) @compileError("only u8 arrays are supported as text params");
                        try self.bindText(position, value);
                    },
                    else => @compileError("unsupported pointer param type"),
                },
                else => @compileError("unsupported pointer param type"),
            },
            .array => |array| {
                if (array.child != u8) @compileError("only u8 arrays are supported as text params");
                try self.bindText(position, value[0..]);
            },
            else => @compileError("unsupported execute param type"),
        }
    }

    /// Bind a BLOB value to a positional parameter (1-indexed). Returns TursoError on failure.
    pub fn bindBlob(self: *Statement, position: usize, value: []const u8) err.TursoError!void {
        if (self.ptr == null) return err.mapStatus(c.TURSO_MISUSE, null, self.allocator);
        var ptr: [*]const u8 = "";
        if (value.len > 0) {
            ptr = value.ptr;
        }
        const status_code = c.turso_statement_bind_positional_blob(self.ptr.?, position, ptr, value.len);
        if (status_code != c.TURSO_OK) {
            return err.mapStatus(status_code, null, self.allocator);
        }
    }

    /// Checked value kind accessor. Invalid statement handles return `error.Misuse`.
    pub fn rowValueKindChecked(self: *Statement, index: usize) err.TursoError!value_mod.ValueKind {
        if (self.ptr == null) return err.mapStatus(c.TURSO_MISUSE, null, self.allocator);
        const kind = c.turso_statement_row_value_kind(self.ptr.?, index);
        return value_mod.ValueKind.fromC(@enumFromInt(kind));
    }

    /// Get the value kind at the given column index for the current row.
    /// Convenience wrapper: invalid handles return `.unknown`. Use `rowValueKindChecked` when misuse must be reported.
    pub fn rowValueKind(self: *Statement, index: usize) value_mod.ValueKind {
        return self.rowValueKindChecked(index) catch .unknown;
    }

    /// Checked INTEGER value accessor. Invalid statement handles return `error.Misuse`.
    pub fn rowValueIntChecked(self: *Statement, index: usize) err.TursoError!i64 {
        if (self.ptr == null) return err.mapStatus(c.TURSO_MISUSE, null, self.allocator);
        return c.turso_statement_row_value_int(self.ptr.?, index);
    }

    /// Get an INTEGER value at the given column index. Returns 0 for non-integer kinds.
    /// Convenience wrapper: invalid handles return 0. Use `rowValueIntChecked` when misuse must be reported.
    pub fn rowValueInt(self: *Statement, index: usize) i64 {
        return self.rowValueIntChecked(index) catch 0;
    }

    /// Checked REAL value accessor. Invalid statement handles return `error.Misuse`.
    pub fn rowValueDoubleChecked(self: *Statement, index: usize) err.TursoError!f64 {
        if (self.ptr == null) return err.mapStatus(c.TURSO_MISUSE, null, self.allocator);
        return c.turso_statement_row_value_double(self.ptr.?, index);
    }

    /// Get a REAL value at the given column index. Returns 0 for non-real kinds.
    /// Convenience wrapper: invalid handles return 0. Use `rowValueDoubleChecked` when misuse must be reported.
    pub fn rowValueDouble(self: *Statement, index: usize) f64 {
        return self.rowValueDoubleChecked(index) catch 0;
    }

    /// Get a TEXT value at the given column index as an owned copy. Returns empty string for non-text kinds.
    pub fn rowValueText(self: *Statement, index: usize) ![]u8 {
        if (self.ptr == null) return err.mapStatus(c.TURSO_MISUSE, null, self.allocator);
        return value_mod.readText(self.ptr.?, index, self.allocator);
    }

    /// Get a BLOB value at the given column index as an owned copy. Returns empty slice for non-blob kinds.
    pub fn rowValueBlob(self: *Statement, index: usize) ![]u8 {
        if (self.ptr == null) return err.mapStatus(c.TURSO_MISUSE, null, self.allocator);
        return value_mod.readBlob(self.ptr.?, index, self.allocator);
    }

    /// Get the value at the given column index as an owned Zig value.
    pub fn rowValue(self: *Statement, index: usize) !value_mod.OwnedValue {
        return switch (try self.rowValueKindChecked(index)) {
            .integer => .{ .integer = try self.rowValueIntChecked(index) },
            .real => .{ .real = try self.rowValueDoubleChecked(index) },
            .text => .{ .text = try self.rowValueText(index) },
            .blob => .{ .blob = try self.rowValueBlob(index) },
            .null => .{ .null = {} },
            .unknown => .{ .unknown = {} },
        };
    }

    /// Checked column count accessor. Invalid statement handles return `error.Misuse`.
    pub fn columnCountChecked(self: *Statement) err.TursoError!i64 {
        if (self.ptr == null) return err.mapStatus(c.TURSO_MISUSE, null, self.allocator);
        return c.turso_statement_column_count(self.ptr.?);
    }

    /// Get the column count for the prepared statement.
    /// Convenience wrapper: invalid handles return 0. Use `columnCountChecked` when misuse must be reported.
    pub fn columnCount(self: *Statement) i64 {
        return self.columnCountChecked() catch 0;
    }

    /// Get the column name at the given index. The returned string is an owned copy allocated with self.allocator; the C-allocated Turso string is freed via turso_str_deinit.
    pub fn columnName(self: *Statement, index: usize) ![]u8 {
        if (self.ptr == null) return err.mapStatus(c.TURSO_MISUSE, null, self.allocator);
        const ptr = c.turso_statement_column_name(self.ptr.?, index);
        defer if (ptr) |p| c.turso_str_deinit(p);
        if (ptr) |p| return try self.allocator.dupe(u8, std.mem.span(p));
        return self.allocator.dupe(u8, "");
    }

    /// Get the declared column type at the given index (e.g. "INTEGER", "TEXT"). Returns empty string for non-available types. The C-allocated Turso string is freed via turso_str_deinit.
    pub fn columnDecltype(self: *Statement, index: usize) ![]u8 {
        if (self.ptr == null) return err.mapStatus(c.TURSO_MISUSE, null, self.allocator);
        const ptr = c.turso_statement_column_decltype(self.ptr.?, index);
        defer if (ptr) |p| c.turso_str_deinit(p);
        if (ptr) |p| return try self.allocator.dupe(u8, std.mem.span(p));
        return self.allocator.dupe(u8, "");
    }

    /// Resolve a named parameter to its 1-indexed positional value.
    /// Returns null when the name is not present.
    pub fn namedPosition(self: *Statement, name: []const u8) err.TursoError!?usize {
        if (self.ptr == null) return err.mapStatus(c.TURSO_MISUSE, null, self.allocator);
        const c_name = try self.allocator.dupeZ(u8, name);
        defer self.allocator.free(c_name);
        const position = c.turso_statement_named_position(self.ptr.?, c_name);
        if (position < 0) return null;
        return @intCast(position);
    }

    /// Checked parameter count accessor. Invalid statement handles return `error.Misuse`.
    pub fn parametersCountChecked(self: *Statement) err.TursoError!i64 {
        if (self.ptr == null) return err.mapStatus(c.TURSO_MISUSE, null, self.allocator);
        return c.turso_statement_parameters_count(self.ptr.?);
    }

    /// Get the total number of parameters for the prepared statement. Returns -1 if the pointer is invalid.
    /// Convenience wrapper: invalid handles return -1. Use `parametersCountChecked` when misuse must be reported.
    pub fn parametersCount(self: *Statement) i64 {
        return self.parametersCountChecked() catch -1;
    }

    /// Execute a single statement to completion, handling TURSO_IO by calling runIO and retrying. Returns row changes count or TursoError.
    fn executeSync(self: *Statement, diagnostic: ?*err.Diagnostic) err.TursoError!u64 {
        while (true) {
            const result = try self.executeOnceWithDiagnostic(diagnostic);
            return switch (result.status_code) {
                .TURSO_OK, .TURSO_DONE => result.changes,
                .TURSO_IO => {
                    try self.runIO();
                    continue;
                },
                else => err.mapStatus(c.TURSO_MISUSE, null, self.allocator),
            };
        }
    }

    fn executeOnceWithDiagnostic(
        self: *Statement,
        diagnostic: ?*err.Diagnostic,
    ) err.TursoError!ExecuteResult {
        if (self.ptr == null) {
            return err.mapStatus(
                c.TURSO_MISUSE,
                null,
                self.allocator,
            );
        }

        var changes: u64 = 0;
        var err_ptr: [*c]const u8 = null;
        const status_code = c.turso_statement_execute(self.ptr.?, &changes, &err_ptr);
        return switch (@as(status.StatusCode, @enumFromInt(status_code))) {
            .TURSO_OK, .TURSO_DONE, .TURSO_IO => .{
                .status_code = @enumFromInt(status_code),
                .changes = changes,
            },
            else => err.mapStatusWithDiagnostic(status_code, err_ptr, self.allocator, diagnostic),
        };
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
            const status_code = try self.stepOnce();
            return switch (status_code) {
                .TURSO_ROW, .TURSO_DONE => status_code,
                .TURSO_IO => {
                    try self.runIO();
                    continue;
                },
                else => err.mapStatus(c.TURSO_MISUSE, null, self.allocator),
            };
        }
    }

    /// Get the number of row modifications made by the most recent executed statement.
    pub fn nChangeChecked(self: *Statement) err.TursoError!i64 {
        if (self.ptr == null) return err.mapStatus(c.TURSO_MISUSE, null, self.allocator);
        return c.turso_statement_n_change(self.ptr.?);
    }

    /// Convenience wrapper: invalid handles return 0. Use `nChangeChecked` when misuse must be reported.
    pub fn nChange(self: *Statement) i64 {
        return self.nChangeChecked() catch 0;
    }

    /// Deinitialize and free the statement handle.
    pub fn deinit(self: *Statement) void {
        if (self.ptr) |p| {
            c.turso_statement_deinit(p);
        }
        self.ptr = null;
    }
};

fn isStaticText(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |ptr| ptr.is_const and ptr.size == .one and switch (@typeInfo(ptr.child)) {
            .array => |array| array.child == u8 and array.sentinel() != null and array.sentinel().? == 0,
            else => false,
        },
        else => false,
    };
}
