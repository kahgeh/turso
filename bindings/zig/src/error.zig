const std = @import("std");
const c = @import("c.zig");

pub const TursoError = struct {
    code: c.turso_status_code_t,
    allocator: std.mem.Allocator,
    owned_message: ?[]u8 = null,
    fallback_message: []const u8 = "",

    pub fn message(self: *const TursoError) []const u8 {
        return if (self.owned_message) |msg| msg else self.fallback_message;
    }

    pub fn deinit(self: *TursoError) void {
        if (self.owned_message) |msg| {
            self.allocator.free(msg);
            self.owned_message = null;
        }
        self.fallback_message = "";
    }

    pub fn format(
        self: TursoError,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("turso error {}: {}", .{
            @intFromEnum(self.code),
            self.message(),
        });
    }
};

pub fn mapStatus(
    status_code: c_int,
    error_ptr: ?[*:0]const u8,
    allocator: std.mem.Allocator,
) TursoError {
    var result = TursoError{
        .code = @enumFromInt(status_code),
        .allocator = allocator,
    };

    const p = error_ptr orelse return result;
    defer c.turso_str_deinit(p);

    const msg = std.mem.span(p);
    if (msg.len == 0) return result;

    result.owned_message = allocator.dupe(u8, msg) catch {
        result.fallback_message = "out of memory while copying Turso error";
        return result;
    };

    return result;
}

pub fn isControlFlow(status_code: c_int) bool {
    return switch (@as(c.turso_status_code_t, @enumFromInt(status_code))) {
        .TURSO_OK, .TURSO_DONE, .TURSO_ROW, .TURSO_IO => true,
        else => false,
    };
}
