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

/// Builder-style database construction for callers that want Rust-like `Builder::new_local(...)` ergonomics.
pub const Builder = struct {
    allocator: std.mem.Allocator,
    config: DatabaseConfig,

    pub fn newLocal(allocator: std.mem.Allocator, path: []const u8) Builder {
        return .{
            .allocator = allocator,
            .config = .{ .path = path },
        };
    }

    pub fn withAsyncIO(self: Builder, async_io: bool) Builder {
        var builder = self;
        builder.config.async_io = async_io;
        return builder;
    }

    pub fn withExperimentalFeatures(self: Builder, experimental_features: []const u8) Builder {
        var builder = self;
        builder.config.experimental_features = experimental_features;
        return builder;
    }

    pub fn withVfs(self: Builder, vfs: []const u8) Builder {
        var builder = self;
        builder.config.vfs = vfs;
        return builder;
    }

    pub fn withEncryption(self: Builder, cipher: []const u8, hexkey: []const u8) Builder {
        var builder = self;
        builder.config.encryption_cipher = cipher;
        builder.config.encryption_hexkey = hexkey;
        return builder;
    }

    /// Build and open the database. The lower-level `Database.init` + `create` path remains available.
    pub fn build(self: Builder) err.TursoError!Database {
        var database = Database.init(self.allocator);
        errdefer database.deinit();
        try database.create(&self.config);
        return database;
    }

    /// Build, open, and connect in one call.
    pub fn connect(self: Builder) err.TursoError!OpenConnection {
        var database = try self.build();
        errdefer database.deinit();

        const conn = try database.connect();
        return .{
            .database = database,
            .connection = conn,
        };
    }
};

/// Owns both a database and one connection created from it.
pub const OpenConnection = struct {
    database: Database,
    connection: connection.Connection,

    pub fn deinit(self: *OpenConnection) void {
        self.connection.deinit();
        self.database.deinit();
    }
};

pub fn newLocal(allocator: std.mem.Allocator, path: []const u8) Builder {
    return Builder.newLocal(allocator, path);
}

/// Wrapper around `turso_database_t` with Zig-friendly lifecycle management.
pub const Database = struct {
    ptr: ?*const c.turso_database_t,
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

        var c_exp_buf: ?[:0]u8 = null;
        var c_vfs_buf: ?[:0]u8 = null;
        var c_enc_cipher_buf: ?[:0]u8 = null;
        var c_enc_hexkey_buf: ?[:0]u8 = null;

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

        var db: ?*const c.turso_database_t = null;
        var err_ptr: [*c]const u8 = null;

        const status = c.turso_database_new(&cc, &db, &err_ptr);
        if (status != c.TURSO_OK) {
            return err.mapStatus(status, err_ptr, self.allocator);
        }

        // Open the database immediately after creation.
        const open_status = c.turso_database_open(db, &err_ptr);
        if (open_status != c.TURSO_OK) {
            // Deinit the newly created handle to avoid leaking it.
            c.turso_database_deinit(db);
            return err.mapStatus(open_status, err_ptr, self.allocator);
        }

        self.ptr = db;
    }

    /// Alias for create() that makes the open lifecycle explicit at call sites.
    pub fn open(self: *Database, config: *const DatabaseConfig) err.TursoError!void {
        try self.create(config);
    }

    /// Connect to the database and return a value handle.
    pub fn connect(self: *Database) err.TursoError!connection.Connection {
        if (self.ptr == null) {
            return err.mapStatus(
                c.TURSO_MISUSE,
                null,
                self.allocator,
            );
        }

        var conn: ?*c.turso_connection_t = null;
        var err_ptr: [*c]const u8 = null;
        const status = c.turso_database_connect(self.ptr.?, &conn, &err_ptr);

        if (status != c.TURSO_OK) {
            return err.mapStatus(status, err_ptr, self.allocator);
        }

        return connection.Connection{
            .ptr = conn,
            .allocator = self.allocator,
        };
    }

    /// Deinitialize and free the database handle.
    pub fn deinit(self: *Database) void {
        if (self.ptr) |p| {
            c.turso_database_deinit(p);
        }
        self.ptr = null;
    }
};
