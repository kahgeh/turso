const std = @import("std");
const c = @import("c.zig");

pub const TursoError = struct {
    code: c.turso_status_code_t,
    message: []const u8,

    pub fn format(
        self: *anyopaque,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        const e = @as(*TursoError, @ptrCast(@alignCast(self)));
        try writer.print("turso error {}: {}", .{ @intFromEnum(e.code), e.message });
    }
};

pub fn mapStatus(status_code: c_int, error_ptr: ?[*:0]const u8) TursoError {
    const code: c.turso_status_code_t = @enumFromInt(status_code);
    if (error_ptr != null and error_ptr.?[0] != 0) {
        return TursoError{
            .code = code,
            .message = std.mem.sliceTo(error_ptr.?, 0),
        };
    }
    return TursoError{
        .code = code,
        .message = "",
    };
}

pub fn isControlFlow(status_code: c_int) bool {
    return switch (@as(c.turso_status_code_t, @enumFromInt(status_code))) {
        .TURSO_OK, .TURSO_DONE, .TURSO_ROW, .TURSO_IO => true,
        else => false,
    };
}
