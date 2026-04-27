const std = @import("std");
const c = @import("c.zig");
const status = @import("status.zig");

/// Zig-side representation of row value kinds, matching turso_type_t from the C API.
pub const ValueKind = enum {
    unknown,
    integer,
    real,
    text,
    blob,
    null,

    pub fn fromC(kind: status.TypeKind) ValueKind {
        return switch (kind) {
            .TURSO_TYPE_INTEGER => .integer,
            .TURSO_TYPE_REAL => .real,
            .TURSO_TYPE_TEXT => .text,
            .TURSO_TYPE_BLOB => .blob,
            .TURSO_TYPE_NULL => .null,
            else => .unknown,
        };
    }
};

/// Owned Zig value copied out of the current statement row.
pub const OwnedValue = union(ValueKind) {
    unknown: void,
    integer: i64,
    real: f64,
    text: []u8,
    blob: []u8,
    null: void,

    pub fn deinit(self: *OwnedValue, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .text => |text| allocator.free(text),
            .blob => |blob| allocator.free(blob),
            else => {},
        }
        self.* = .{ .unknown = {} };
    }
};

/// Borrowed row value valid until the statement is stepped, reset, or finalized.
pub const BorrowedValue = union(ValueKind) {
    unknown: void,
    integer: i64,
    real: f64,
    text: []const u8,
    blob: []const u8,
    null: void,
};

/// Read an INTEGER value at the given index. Returns 0 for non-integer kinds.
pub fn readInt(
    statement_ptr: *c.turso_statement_t,
    index: usize,
) i64 {
    return c.turso_statement_row_value_int(statement_ptr, index);
}

/// Read a REAL value at the given index. Returns 0 for non-real kinds.
pub fn readDouble(
    statement_ptr: *c.turso_statement_t,
    index: usize,
) f64 {
    return c.turso_statement_row_value_double(statement_ptr, index);
}

/// Read a TEXT value at the given index and return an owned copy.
/// Returns empty string for non-text kinds.
pub fn readText(
    statement_ptr: *c.turso_statement_t,
    index: usize,
    allocator: std.mem.Allocator,
) ![]u8 {
    const n = c.turso_statement_row_value_bytes_count(statement_ptr, index);
    if (n <= 0) return allocator.dupe(u8, "");
    const len: usize = @intCast(n);

    const ptr = c.turso_statement_row_value_bytes_ptr(statement_ptr, index);
    if (ptr == null) return allocator.dupe(u8, "");

    const out = try allocator.alloc(u8, len);
    std.mem.copyForwards(u8, out, ptr[0..len]);
    return out;
}

/// Read a BLOB value at the given index and return an owned copy.
/// Returns empty slice for non-blob kinds.
pub fn readBlob(
    statement_ptr: *c.turso_statement_t,
    index: usize,
    allocator: std.mem.Allocator,
) ![]u8 {
    const n = c.turso_statement_row_value_bytes_count(statement_ptr, index);
    if (n <= 0) return try allocator.dupe(u8, "");
    const len: usize = @intCast(n);

    const ptr = c.turso_statement_row_value_bytes_ptr(statement_ptr, index);
    if (ptr == null) return try allocator.dupe(u8, "");

    const out = try allocator.alloc(u8, len);
    std.mem.copyForwards(u8, out, ptr[0..len]);
    return out;
}

/// Read TEXT or BLOB bytes as a borrowed slice from the current statement row.
/// The slice is valid until the statement is stepped, reset, or finalized.
pub fn readBytesBorrowed(
    statement_ptr: *c.turso_statement_t,
    index: usize,
) []const u8 {
    const n = c.turso_statement_row_value_bytes_count(statement_ptr, index);
    if (n <= 0) return "";
    const len: usize = @intCast(n);

    const ptr = c.turso_statement_row_value_bytes_ptr(statement_ptr, index);
    if (ptr == null) return "";

    return ptr[0..len];
}
