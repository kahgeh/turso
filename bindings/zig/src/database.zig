const std = @import("std");
const c = @import("c.zig");
const err = @import("error.zig");
const connection = @import("connection.zig");

/// Configuration for creating/opening a database.
pub const DatabaseConfig = struct {
    /// Path to the database file or `:memory:`
    path: []const u8,
    /// Enable async IO (caller-driven) when true.
    async_io: bool = false,
    /// Optional comma-separated list of experimental features.
    experimental_features: ?[]const u8 = null,
    /// Optional VFS backend ("memory", "syscall", "io_uring").
    vfs: ?[]const u8 = null,
    /// Optional encryption cipher (requires "encryption" in experimental_features).
    encryption_cipher: ?[]const u8 = null,
    /// Optional encryption hex key (requires "encryption" in experimental_features).
    encryption_hexkey: ?[]const u8 = null,

    pub fn deinit(self: *DatabaseConfig) void {
        // Caller owns the string slices; nothing to free here.
        _ = self;
    }
};

/// Wrapper around `turso_database_t` with Zig-friendly lifecycle management.
pub const Database = struct {
    ptr: ?*c.turso_database_t,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Database {
        return Database{
            .ptr = null,
            .allocator = allocator,
        };
    }

    /// Create a database handle and open it. Returns TursoError on failure.
    pub fn create(self: *Database, config: *const DatabaseConfig) err.TursoError!void {
        // Allocate zero-terminated copies for C FFI.
        const path_owned = try self.allocator.dupeZ(u8, config.path);

        var c_exp_buf: ?[]u8 = null;
        var c_vfs_buf: ?[]u8 = null;
        var c_enc_cipher_buf: ?[]u8 = null;
        var c_enc_hexkey_buf: ?[]u8 = null;

        if (config.experimental_features) |exp| {
            c_exp_buf = try self.allocator.dupeZ(u8, exp);
        }
        if (config.vfs) |v| {
            c_vfs_buf = try self.allocator.dupeZ(u8, v);
        }
        if (config.encryption_cipher) |ec| {
            c_enc_cipher_buf = try self.allocator.dupeZ(u8, ec);
        }
        if (config.encryption_hexkey) |eh| {
            c_enc_hexkey_buf = try self.allocator.dupeZ(u8, eh);
        }

        // Free all owned buffers on any exit path.
        defer {
            self.allocator.free(path_owned);
            if (c_exp_buf) |b| self.allocator.free(b);
            if (c_vfs_buf) |b| self.allocator.free(b);
            if (c_enc_cipher_buf) |b| self.allocator.free(b);
            if (c_enc_hexkey_buf) |b| self.allocator.free(b);
        }

        var cc: c.turso_database_config_t = .{
            .async_io = if (config.async_io) 1 else 0,
            .path = path_owned.ptr,
            .experimental_features = if (c_exp_buf) |b| b.ptr else null,
            .vfs = if (c_vfs_buf) |b| b.ptr else null,
            .encryption_cipher = if (c_enc_cipher_buf) |b| b.ptr else null,
            .encryption_hexkey = if (c_enc_hexkey_buf) |b| b.ptr else null,
        };

        var db: ?*c.turso_database_t = null;
        var err_ptr: [*:0]const u8 = null;

        const status = c.turso_database_new(&cc, &db, &err_ptr);
        if (status != @intFromEnum(c.turso_status_code_t.TURSO_OK)) {
            return err.mapStatus(status, err_ptr, self.allocator);
        }

        // Open the database immediately after creation.
        const open_status = c.turso_database_open(db, &err_ptr);
        if (open_status != @intFromEnum(c.turso_status_code_t.TURSO_OK)) {
            // Deinit the newly created handle to avoid leaking it.
            c.turso_database_deinit(db);
            return err.mapStatus(open_status, err_ptr, self.allocator);
        }

        self.ptr = db;
    }

    /// Connect to the database and return a new Connection.
    pub fn connect(self: *Database) err.TursoError!*connection.Connection {
        if (self.ptr == null) {
            return err.mapStatus(
                @intFromEnum(c.turso_status_code_t.TURSO_MISUSE),
                null,
                self.allocator,
            );
        }

        var conn: ?*c.turso_connection_t = null;
        var err_ptr: [*:0]const u8 = null;
        const status = c.turso_database_connect(self.ptr.?, &conn, &err_ptr);

        if (status != @intFromEnum(c.turso_status_code_t.TURSO_OK)) {
            return err.mapStatus(status, err_ptr, self.allocator);
        }

        const connection_wrapper = self.allocator.create(connection.Connection) catch |e| {
            c.turso_connection_deinit(conn);
            var msg_buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&msg_buf, "failed to allocate Connection: {}", .{e}) catch "failed to allocate Connection";
            return err.TursoError{
                .code = @enumFromInt(@intFromEnum(c.turso_status_code_t.TURSO_ERROR)),
                .allocator = self.allocator,
                .owned_message = try self.allocator.dupe(u8, msg),
            };
        };
        connection_wrapper.* = connection.Connection{
            .ptr = conn,
            .allocator = self.allocator,
        };
        return connection_wrapper;
    }

    /// Deinitialize and free the database handle.
    pub fn deinit(self: *Database) void {
        if (self.ptr) |p| {
            c.turso_database_deinit(p);
        }
        self.ptr = null;
    }
};
