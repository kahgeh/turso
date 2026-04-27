const std = @import("std");
const turso = @import("turso");

pub const Fixture = struct {
    db: turso.db.Database,
    conn: turso.conn.Connection,
    closed: bool = false,

    pub fn close(self: *Fixture) !void {
        if (self.closed) return;
        try self.conn.close();
        self.closed = true;
    }

    pub fn deinit(self: *Fixture) void {
        if (!self.closed) {
            self.close() catch |close_err| {
                std.debug.panic("connection close failed during test cleanup: {}", .{close_err});
            };
        }
        self.conn.deinit();
        self.db.deinit();
    }
};

pub const StatementGuard = struct {
    stmt: turso.stmt.Statement,
    finalized: bool = false,

    pub fn finalize(self: *StatementGuard) !void {
        if (self.finalized) return;
        try self.stmt.finalize();
        self.finalized = true;
    }

    pub fn deinit(self: *StatementGuard) void {
        if (!self.finalized) {
            self.finalize() catch |finalize_err| {
                std.debug.panic("statement finalize failed during test cleanup: {}", .{finalize_err});
            };
        }
        self.stmt.deinit();
    }
};

pub fn openInMemory(allocator: std.mem.Allocator) !Fixture {
    var db = turso.db.Database.init(allocator);
    const config = turso.db.DatabaseConfig{
        .path = ":memory:",
    };
    try db.create(&config);
    errdefer db.deinit();

    var conn = try db.connect();
    errdefer conn.deinit();

    return Fixture{
        .db = db,
        .conn = conn,
    };
}

pub fn prepare(
    allocator: std.mem.Allocator,
    conn: *turso.conn.Connection,
    sql: []const u8,
) !StatementGuard {
    _ = allocator;
    return StatementGuard{
        .stmt = try conn.prepareSingle(sql),
    };
}
