const std = @import("std");
const raw = @import("c.zig");
const c = @import("sync_c.zig");
const connection = @import("connection.zig");
const err = @import("error.zig");

const default_client_name = "turso-sync-zig";

pub const SyncError = err.TursoError || error{
    InvalidResult,
    UnsupportedSyncIo,
};

pub const RemoteEncryptionCipher = enum {
    aes_256_gcm,
    aes_128_gcm,
    chacha20_poly1305,
    aegis_128l,
    aegis_128x2,
    aegis_128x4,
    aegis_256,
    aegis_256x2,
    aegis_256x4,

    pub fn reservedBytes(self: RemoteEncryptionCipher) i32 {
        return switch (self) {
            .aes_256_gcm, .aes_128_gcm, .chacha20_poly1305 => 28,
            .aegis_128l, .aegis_128x2, .aegis_128x4 => 32,
            .aegis_256, .aegis_256x2, .aegis_256x4 => 48,
        };
    }

    pub fn cName(self: RemoteEncryptionCipher) []const u8 {
        return switch (self) {
            .aes_256_gcm => "aes256gcm",
            .aes_128_gcm => "aes128gcm",
            .chacha20_poly1305 => "chacha20poly1305",
            .aegis_128l => "aegis128l",
            .aegis_128x2 => "aegis128x2",
            .aegis_128x4 => "aegis128x4",
            .aegis_256 => "aegis256",
            .aegis_256x2 => "aegis256x2",
            .aegis_256x4 => "aegis256x4",
        };
    }
};

pub const PartialBootstrapStrategy = union(enum) {
    prefix: i32,
    query: []const u8,
};

pub const PartialSyncOpts = struct {
    strategy: PartialBootstrapStrategy,
    segment_size: usize = 0,
    prefetch: bool = false,
};

pub const DatabaseConfig = struct {
    path: []const u8,
    experimental_features: ?[]const u8 = null,
    vfs: ?[]const u8 = null,
    encryption_cipher: ?[]const u8 = null,
    encryption_hexkey: ?[]const u8 = null,
};

pub const SyncConfig = struct {
    path: []const u8,
    remote_url: ?[]const u8 = null,
    client_name: []const u8 = default_client_name,
    long_poll_timeout_ms: i32 = 0,
    bootstrap_if_empty: bool = true,
    reserved_bytes: i32 = 0,
    partial_sync_opts: ?PartialSyncOpts = null,
    remote_encryption_key: ?[]const u8 = null,
    remote_encryption_cipher: ?[]const u8 = null,
};

const OwnedConfig = struct {
    allocator: std.mem.Allocator,
    db_path: ?[:0]u8 = null,
    db_experimental_features: ?[:0]u8 = null,
    db_vfs: ?[:0]u8 = null,
    db_encryption_cipher: ?[:0]u8 = null,
    db_encryption_hexkey: ?[:0]u8 = null,
    sync_path: ?[:0]u8 = null,
    sync_remote_url: ?[:0]u8 = null,
    sync_client_name: ?[:0]u8 = null,
    sync_query: ?[:0]u8 = null,
    sync_remote_encryption_key: ?[:0]u8 = null,
    sync_remote_encryption_cipher: ?[:0]u8 = null,
    db: raw.turso_database_config_t,
    sync: c.turso_sync_database_config_t,

    fn init(
        allocator: std.mem.Allocator,
        db_config: DatabaseConfig,
        sync_config: SyncConfig,
    ) !OwnedConfig {
        var self: OwnedConfig = undefined;
        self = .{
            .allocator = allocator,
            .db_path = try allocator.dupeZ(u8, db_config.path),
            .db = undefined,
            .sync = undefined,
        };
        errdefer self.deinit();

        self.sync_path = try allocator.dupeZ(u8, sync_config.path);
        self.sync_client_name = try allocator.dupeZ(u8, sync_config.client_name);
        if (db_config.experimental_features) |value| self.db_experimental_features = try allocator.dupeZ(u8, value);
        if (db_config.vfs) |value| self.db_vfs = try allocator.dupeZ(u8, value);
        if (db_config.encryption_cipher) |value| self.db_encryption_cipher = try allocator.dupeZ(u8, value);
        if (db_config.encryption_hexkey) |value| self.db_encryption_hexkey = try allocator.dupeZ(u8, value);
        if (sync_config.remote_url) |value| self.sync_remote_url = try dupeNormalizedUrlZ(allocator, value);
        if (sync_config.remote_encryption_key) |value| self.sync_remote_encryption_key = try allocator.dupeZ(u8, value);
        if (sync_config.remote_encryption_cipher) |value| self.sync_remote_encryption_cipher = try allocator.dupeZ(u8, value);

        var partial_prefix: i32 = 0;
        var partial_query: ?[*:0]u8 = null;
        var partial_segment_size: usize = 0;
        var partial_prefetch = false;
        if (sync_config.partial_sync_opts) |opts| {
            partial_segment_size = opts.segment_size;
            partial_prefetch = opts.prefetch;
            switch (opts.strategy) {
                .prefix => |prefix| partial_prefix = prefix,
                .query => |query| {
                    self.sync_query = try allocator.dupeZ(u8, query);
                    partial_query = self.sync_query.?.ptr;
                },
            }
        }

        self.db = .{
            .async_io = 1,
            .path = self.db_path.?.ptr,
            .experimental_features = if (self.db_experimental_features) |value| value.ptr else null,
            .vfs = if (self.db_vfs) |value| value.ptr else null,
            .encryption_cipher = if (self.db_encryption_cipher) |value| value.ptr else null,
            .encryption_hexkey = if (self.db_encryption_hexkey) |value| value.ptr else null,
        };
        self.sync = .{
            .path = self.sync_path.?.ptr,
            .remote_url = if (self.sync_remote_url) |value| value.ptr else null,
            .client_name = self.sync_client_name.?.ptr,
            .long_poll_timeout_ms = sync_config.long_poll_timeout_ms,
            .bootstrap_if_empty = sync_config.bootstrap_if_empty,
            .reserved_bytes = sync_config.reserved_bytes,
            .partial_bootstrap_strategy_prefix = partial_prefix,
            .partial_bootstrap_strategy_query = partial_query,
            .partial_bootstrap_segment_size = partial_segment_size,
            .partial_bootstrap_prefetch = partial_prefetch,
            .remote_encryption_key = if (self.sync_remote_encryption_key) |value| value.ptr else null,
            .remote_encryption_cipher = if (self.sync_remote_encryption_cipher) |value| value.ptr else null,
        };
        return self;
    }

    fn deinit(self: *OwnedConfig) void {
        if (self.db_path) |value| self.allocator.free(value);
        if (self.db_experimental_features) |value| self.allocator.free(value);
        if (self.db_vfs) |value| self.allocator.free(value);
        if (self.db_encryption_cipher) |value| self.allocator.free(value);
        if (self.db_encryption_hexkey) |value| self.allocator.free(value);
        if (self.sync_path) |value| self.allocator.free(value);
        if (self.sync_remote_url) |value| self.allocator.free(value);
        if (self.sync_client_name) |value| self.allocator.free(value);
        if (self.sync_query) |value| self.allocator.free(value);
        if (self.sync_remote_encryption_key) |value| self.allocator.free(value);
        if (self.sync_remote_encryption_cipher) |value| self.allocator.free(value);
    }
};

pub const Stats = struct {
    cdc_operations: i64,
    main_wal_size: i64,
    revert_wal_size: i64,
    last_pull_unix_time: i64,
    last_push_unix_time: i64,
    network_sent_bytes: i64,
    network_received_bytes: i64,
    revision: []u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Stats) void {
        self.allocator.free(self.revision);
        self.revision = &.{};
    }
};

pub const Changes = struct {
    ptr: ?*const c.turso_sync_changes_t,

    pub fn deinit(self: *Changes) void {
        if (self.ptr) |ptr| c.turso_sync_changes_deinit(ptr);
        self.ptr = null;
    }
};

pub const Operation = struct {
    ptr: ?*const c.turso_sync_operation_t,
    allocator: std.mem.Allocator,

    fn deinit(self: *Operation) void {
        if (self.ptr) |ptr| c.turso_sync_operation_deinit(ptr);
        self.ptr = null;
    }

    fn continueOp(self: *Operation) SyncError!c.turso_status_code_t {
        if (self.ptr == null) return error.Misuse;
        var err_ptr: [*c]const u8 = null;
        const status = c.turso_sync_operation_resume(self.ptr.?, &err_ptr);
        if (isControlFlow(status)) return status;
        return mapStatus(status, err_ptr, self.allocator);
    }

    fn expectResultKind(self: *Operation, expected: c.turso_sync_operation_result_type_t) SyncError!void {
        if (self.ptr == null) return error.Misuse;
        if (c.turso_sync_operation_result_kind(self.ptr.?) != expected) return error.InvalidResult;
    }
};

pub const HttpRequest = struct {
    url: []const u8,
    method: []const u8,
    path: []const u8,
    body: []const u8,
    headers: []const Header,
};

pub const Header = struct {
    key: []const u8,
    value: []const u8,
};

pub const HttpResponse = struct {
    status: i32,
    body: []const u8 = &.{},
    owned_body: ?[]u8 = null,
};

pub const IoExecutor = struct {
    context: ?*anyopaque = null,
    http: *const fn (context: ?*anyopaque, allocator: std.mem.Allocator, request: HttpRequest) anyerror!HttpResponse,
};

pub const Database = struct {
    ptr: ?*const c.turso_sync_database_t,
    allocator: std.mem.Allocator,
    io_executor: ?IoExecutor = null,
    auth_token: ?[]u8 = null,

    pub fn init(allocator: std.mem.Allocator) Database {
        return .{ .ptr = null, .allocator = allocator };
    }

    pub fn createHandle(
        self: *Database,
        db_config: DatabaseConfig,
        sync_config: SyncConfig,
    ) SyncError!void {
        var owned = try OwnedConfig.init(self.allocator, db_config, sync_config);
        defer owned.deinit();

        var db_ptr: ?*const c.turso_sync_database_t = null;
        var err_ptr: [*c]const u8 = null;
        const status = c.turso_sync_database_new(
            @ptrCast(&owned.db),
            &owned.sync,
            &db_ptr,
            &err_ptr,
        );
        if (status != c.TURSO_OK) return mapStatus(status, err_ptr, self.allocator);

        self.ptr = db_ptr;
    }

    pub fn setIoExecutor(self: *Database, executor: IoExecutor) void {
        self.io_executor = executor;
    }

    pub fn setAuthToken(self: *Database, token: []const u8) !void {
        if (self.auth_token) |owned| self.allocator.free(owned);
        self.auth_token = try self.allocator.dupe(u8, token);
    }

    pub fn create(self: *Database) SyncError!void {
        var op = try self.startVoid(c.turso_sync_database_create);
        defer op.deinit();
        try self.driveOperation(&op);
        try op.expectResultKind(c.TURSO_ASYNC_RESULT_NONE);
    }

    pub fn open(self: *Database) SyncError!void {
        var op = try self.startVoid(c.turso_sync_database_open);
        defer op.deinit();
        try self.driveOperation(&op);
        try op.expectResultKind(c.TURSO_ASYNC_RESULT_NONE);
    }

    pub fn connect(self: *Database) SyncError!connection.Connection {
        var op = try self.startVoid(c.turso_sync_database_connect);
        defer op.deinit();
        try self.driveOperation(&op);
        try op.expectResultKind(c.TURSO_ASYNC_RESULT_CONNECTION);

        var conn_ptr: ?*const c.turso_connection_t = null;
        const status = c.turso_sync_operation_result_extract_connection(op.ptr.?, &conn_ptr);
        if (status != c.TURSO_OK) return mapStatus(status, null, self.allocator);
        return .{
            .ptr = @ptrCast(@constCast(conn_ptr)),
            .allocator = self.allocator,
            .extra_io = .{
                .context = self,
                .run = runConnectionIo,
            },
        };
    }

    pub fn push(self: *Database) SyncError!void {
        var op = try self.startVoid(c.turso_sync_database_push_changes);
        defer op.deinit();
        try self.driveOperation(&op);
        try op.expectResultKind(c.TURSO_ASYNC_RESULT_NONE);
    }

    pub fn pull(self: *Database) SyncError!bool {
        var wait_op = try self.startVoid(c.turso_sync_database_wait_changes);
        defer wait_op.deinit();
        try self.driveOperation(&wait_op);
        try wait_op.expectResultKind(c.TURSO_ASYNC_RESULT_CHANGES);

        var changes_ptr: ?*const c.turso_sync_changes_t = null;
        const status = c.turso_sync_operation_result_extract_changes(wait_op.ptr.?, &changes_ptr);
        if (status != c.TURSO_OK) return mapStatus(status, null, self.allocator);
        if (changes_ptr == null) return false;

        var changes = Changes{ .ptr = changes_ptr };
        try self.applyChanges(&changes);
        return true;
    }

    pub fn applyChanges(self: *Database, changes: *Changes) SyncError!void {
        if (self.ptr == null or changes.ptr == null) return error.Misuse;
        var op_ptr: ?*const c.turso_sync_operation_t = null;
        var err_ptr: [*c]const u8 = null;
        const status = c.turso_sync_database_apply_changes(self.ptr.?, changes.ptr.?, &op_ptr, &err_ptr);
        changes.ptr = null;
        if (status != c.TURSO_OK) return mapStatus(status, err_ptr, self.allocator);

        var op = Operation{ .ptr = op_ptr, .allocator = self.allocator };
        defer op.deinit();
        try self.driveOperation(&op);
        try op.expectResultKind(c.TURSO_ASYNC_RESULT_NONE);
    }

    pub fn checkpoint(self: *Database) SyncError!void {
        var op = try self.startVoid(c.turso_sync_database_checkpoint);
        defer op.deinit();
        try self.driveOperation(&op);
        try op.expectResultKind(c.TURSO_ASYNC_RESULT_NONE);
    }

    pub fn stats(self: *Database) SyncError!Stats {
        var op = try self.startVoid(c.turso_sync_database_stats);
        defer op.deinit();
        try self.driveOperation(&op);
        try op.expectResultKind(c.TURSO_ASYNC_RESULT_STATS);

        var raw_stats: c.turso_sync_stats_t = undefined;
        const status = c.turso_sync_operation_result_extract_stats(op.ptr.?, &raw_stats);
        if (status != c.TURSO_OK) return mapStatus(status, null, self.allocator);

        const revision = try self.allocator.dupe(u8, sliceBytes(raw_stats.revision));
        return .{
            .cdc_operations = raw_stats.cdc_operations,
            .main_wal_size = raw_stats.main_wal_size,
            .revert_wal_size = raw_stats.revert_wal_size,
            .last_pull_unix_time = raw_stats.last_pull_unix_time,
            .last_push_unix_time = raw_stats.last_push_unix_time,
            .network_sent_bytes = raw_stats.network_sent_bytes,
            .network_received_bytes = raw_stats.network_received_bytes,
            .revision = revision,
            .allocator = self.allocator,
        };
    }

    fn startVoid(
        self: *Database,
        comptime starter: fn (
            *const c.turso_sync_database_t,
            *?*const c.turso_sync_operation_t,
            [*c][*c]const u8,
        ) callconv(.c) c.turso_status_code_t,
    ) SyncError!Operation {
        if (self.ptr == null) return error.Misuse;
        var op_ptr: ?*const c.turso_sync_operation_t = null;
        var err_ptr: [*c]const u8 = null;
        const status = starter(self.ptr.?, &op_ptr, &err_ptr);
        if (status != c.TURSO_OK) return mapStatus(status, err_ptr, self.allocator);
        return .{ .ptr = op_ptr, .allocator = self.allocator };
    }

    fn driveOperation(self: *Database, op: *Operation) SyncError!void {
        while (true) {
            switch (try op.continueOp()) {
                c.TURSO_DONE => return,
                c.TURSO_IO => try self.drainIoQueue(),
                c.TURSO_OK => {},
                else => return error.UnexpectedStatus,
            }
        }
    }

    fn drainIoQueue(self: *Database) SyncError!void {
        while (true) {
            var item_ptr: ?*const c.turso_sync_io_item_t = null;
            var err_ptr: [*c]const u8 = null;
            const status = c.turso_sync_database_io_take_item(self.ptr.?, &item_ptr, &err_ptr);
            if (status != c.TURSO_OK) return mapStatus(status, err_ptr, self.allocator);
            if (item_ptr == null) break;

            var item = IoItem{ .ptr = item_ptr.?, .allocator = self.allocator };
            defer item.deinit();
            try self.handleIoItem(&item);
        }

        var err_ptr: [*c]const u8 = null;
        const callback_status = c.turso_sync_database_io_step_callbacks(self.ptr.?, &err_ptr);
        if (callback_status != c.TURSO_OK) return mapStatus(callback_status, err_ptr, self.allocator);
    }

    fn runConnectionIo(context: *anyopaque) err.TursoError!void {
        const self: *Database = @ptrCast(@alignCast(context));
        self.drainIoQueue() catch |drain_err| switch (drain_err) {
            error.InvalidResult, error.UnsupportedSyncIo => return error.IOError,
            else => |mapped_err| return mapped_err,
        };
    }

    fn handleIoItem(self: *Database, item: *IoItem) SyncError!void {
        switch (c.turso_sync_database_io_request_kind(item.ptr)) {
            c.TURSO_SYNC_IO_FULL_READ => try item.completeFullRead(),
            c.TURSO_SYNC_IO_FULL_WRITE => try item.completeFullWrite(),
            c.TURSO_SYNC_IO_HTTP => {
                if (self.io_executor) |executor| {
                    try item.completeHttp(self.allocator, executor, self.auth_token);
                } else {
                    try item.completeHttp(self.allocator, defaultIoExecutor(), self.auth_token);
                }
            },
            c.TURSO_SYNC_IO_NONE => try item.done(),
            else => return error.UnsupportedSyncIo,
        }
    }

    pub fn deinit(self: *Database) void {
        if (self.ptr) |ptr| c.turso_sync_database_deinit(ptr);
        if (self.auth_token) |token| self.allocator.free(token);
        self.ptr = null;
        self.auth_token = null;
    }
};

const IoItem = struct {
    ptr: *const c.turso_sync_io_item_t,
    allocator: std.mem.Allocator,

    fn deinit(self: *IoItem) void {
        c.turso_sync_database_io_item_deinit(self.ptr);
    }

    fn completeFullRead(self: *IoItem) SyncError!void {
        var request: c.turso_sync_io_full_read_request_t = undefined;
        var status = c.turso_sync_database_io_request_full_read(self.ptr, &request);
        if (status != c.TURSO_OK) return mapStatus(status, null, self.allocator);

        const path = sliceBytes(request.path);
        var threaded: std.Io.Threaded = .init(self.allocator, .{});
        defer threaded.deinit();

        const content = std.Io.Dir.cwd().readFileAlloc(threaded.io(), path, self.allocator, .unlimited) catch |read_err| switch (read_err) {
            error.FileNotFound => try self.allocator.dupe(u8, &.{}),
            else => {
                try self.poison(@errorName(read_err));
                return error.IOError;
            },
        };
        defer self.allocator.free(content);

        status = try self.pushBuffer(content);
        if (status != c.TURSO_OK) return mapStatus(status, null, self.allocator);
        try self.done();
    }

    fn completeFullWrite(self: *IoItem) SyncError!void {
        var request: c.turso_sync_io_full_write_request_t = undefined;
        const status = c.turso_sync_database_io_request_full_write(self.ptr, &request);
        if (status != c.TURSO_OK) return mapStatus(status, null, self.allocator);

        const path = sliceBytes(request.path);
        const content = sliceBytes(request.content);
        const tmp_path = try std.fmt.allocPrint(self.allocator, "{s}.tmp", .{path});
        defer self.allocator.free(tmp_path);

        var threaded: std.Io.Threaded = .init(self.allocator, .{});
        defer threaded.deinit();

        std.Io.Dir.cwd().writeFile(threaded.io(), .{ .sub_path = tmp_path, .data = content }) catch |write_err| {
            try self.poison(@errorName(write_err));
            return error.IOError;
        };
        std.Io.Dir.rename(.cwd(), tmp_path, .cwd(), path, threaded.io()) catch |rename_err| {
            try self.poison(@errorName(rename_err));
            return error.IOError;
        };

        try self.done();
    }

    fn completeHttp(
        self: *IoItem,
        allocator: std.mem.Allocator,
        executor: IoExecutor,
        auth_token: ?[]const u8,
    ) SyncError!void {
        var request: c.turso_sync_io_http_request_t = undefined;
        var status = c.turso_sync_database_io_request_http(self.ptr, &request);
        if (status != c.TURSO_OK) return mapStatus(status, null, self.allocator);

        const header_count: usize = @intCast(request.headers);
        var add_auth = false;
        var auth_value: ?[]u8 = null;
        defer if (auth_value) |value| allocator.free(value);

        const headers = try allocator.alloc(Header, header_count + if (auth_token != null) @as(usize, 1) else 0);
        defer allocator.free(headers);
        for (headers[0..header_count], 0..) |*header, index| {
            var raw_header: c.turso_sync_io_http_header_t = undefined;
            status = c.turso_sync_database_io_request_http_header(self.ptr, index, &raw_header);
            if (status != c.TURSO_OK) return mapStatus(status, null, self.allocator);
            header.* = .{
                .key = sliceBytes(raw_header.key),
                .value = sliceBytes(raw_header.value),
            };
            if (std.ascii.eqlIgnoreCase(header.key, "authorization")) add_auth = false;
        }

        var request_headers = headers[0..header_count];
        if (auth_token) |token| {
            add_auth = true;
            for (request_headers) |header| {
                if (std.ascii.eqlIgnoreCase(header.key, "authorization")) {
                    add_auth = false;
                    break;
                }
            }
            if (add_auth) {
                auth_value = try std.fmt.allocPrint(allocator, "Bearer {s}", .{token});
                headers[header_count] = .{
                    .key = "authorization",
                    .value = auth_value.?,
                };
                request_headers = headers[0 .. header_count + 1];
            }
        }

        const response = executor.http(executor.context, allocator, .{
            .url = sliceBytes(request.url),
            .method = sliceBytes(request.method),
            .path = sliceBytes(request.path),
            .body = sliceBytes(request.body),
            .headers = request_headers,
        }) catch |http_err| {
            try self.poison(@errorName(http_err));
            return error.IOError;
        };
        defer if (response.owned_body) |body| allocator.free(body);

        status = c.turso_sync_database_io_status(self.ptr, response.status);
        if (status != c.TURSO_OK) return mapStatus(status, null, self.allocator);
        status = try self.pushBuffer(response.body);
        if (status != c.TURSO_OK) return mapStatus(status, null, self.allocator);
        try self.done();
    }

    fn pushBuffer(self: *IoItem, buffer: []const u8) SyncError!c.turso_status_code_t {
        var slice = c.turso_slice_ref_t{
            .ptr = buffer.ptr,
            .len = buffer.len,
        };
        return c.turso_sync_database_io_push_buffer(self.ptr, &slice);
    }

    fn poison(self: *IoItem, message: []const u8) SyncError!void {
        var slice = c.turso_slice_ref_t{
            .ptr = message.ptr,
            .len = message.len,
        };
        const status = c.turso_sync_database_io_poison(self.ptr, &slice);
        if (status != c.TURSO_OK) return mapStatus(status, null, self.allocator);
    }

    fn done(self: *IoItem) SyncError!void {
        const status = c.turso_sync_database_io_done(self.ptr);
        if (status != c.TURSO_OK) return mapStatus(status, null, self.allocator);
    }
};

pub const Builder = struct {
    allocator: std.mem.Allocator,
    db_config: DatabaseConfig,
    sync_config: SyncConfig,
    io_executor: ?IoExecutor = null,
    auth_token: ?[]const u8 = null,

    pub fn newRemote(allocator: std.mem.Allocator, path: []const u8) Builder {
        return .{
            .allocator = allocator,
            .db_config = .{ .path = path },
            .sync_config = .{ .path = path },
        };
    }

    pub fn withRemoteUrl(self: Builder, url: []const u8) Builder {
        var builder = self;
        builder.sync_config.remote_url = url;
        return builder;
    }

    pub fn withAuthToken(self: Builder, token: []const u8) Builder {
        var builder = self;
        builder.auth_token = token;
        return builder;
    }

    pub fn withClientName(self: Builder, name: []const u8) Builder {
        var builder = self;
        builder.sync_config.client_name = name;
        return builder;
    }

    pub fn withLongPollTimeoutMs(self: Builder, ms: i32) Builder {
        var builder = self;
        builder.sync_config.long_poll_timeout_ms = ms;
        return builder;
    }

    pub fn bootstrapIfEmpty(self: Builder, enabled: bool) Builder {
        var builder = self;
        builder.sync_config.bootstrap_if_empty = enabled;
        return builder;
    }

    pub fn withPartialSyncOptsExperimental(self: Builder, opts: PartialSyncOpts) Builder {
        var builder = self;
        builder.sync_config.partial_sync_opts = opts;
        return builder;
    }

    pub fn withRemoteEncryption(self: Builder, base64_key: []const u8, cipher: RemoteEncryptionCipher) Builder {
        var builder = self;
        builder.sync_config.remote_encryption_key = base64_key;
        builder.sync_config.remote_encryption_cipher = cipher.cName();
        builder.sync_config.reserved_bytes = cipher.reservedBytes();
        return builder;
    }

    pub fn withRemoteEncryptionKey(self: Builder, base64_key: []const u8) Builder {
        var builder = self;
        builder.sync_config.remote_encryption_key = base64_key;
        return builder;
    }

    pub fn withIoExecutor(self: Builder, executor: IoExecutor) Builder {
        var builder = self;
        builder.io_executor = executor;
        return builder;
    }

    pub fn build(self: Builder) SyncError!Database {
        var database = Database.init(self.allocator);
        errdefer database.deinit();
        try database.createHandle(self.db_config, self.sync_config);
        if (self.io_executor) |executor| database.setIoExecutor(executor);
        if (self.auth_token) |token| try database.setAuthToken(token);
        try database.create();
        return database;
    }
};

pub fn defaultIoExecutor() IoExecutor {
    return .{ .http = defaultHttp };
}

fn defaultHttp(
    _: ?*anyopaque,
    allocator: std.mem.Allocator,
    request: HttpRequest,
) !HttpResponse {
    const method = std.meta.stringToEnum(std.http.Method, request.method) orelse return error.UnsupportedHttpMethod;
    const url = try buildHttpUrl(allocator, request.url, request.path);
    defer allocator.free(url);

    const headers = try allocator.alloc(std.http.Header, request.headers.len);
    defer allocator.free(headers);
    for (headers, request.headers) |*header, source| {
        header.* = .{
            .name = source.key,
            .value = source.value,
        };
    }

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    var client: std.http.Client = .{
        .allocator = allocator,
        .io = threaded.io(),
    };
    defer client.deinit();

    var body_writer: std.Io.Writer.Allocating = .init(allocator);
    errdefer body_writer.deinit();

    const result = try client.fetch(.{
        .location = .{ .url = url },
        .method = method,
        .payload = if (request.body.len == 0 and !method.requestHasBody()) null else request.body,
        .extra_headers = headers,
        .response_writer = &body_writer.writer,
    });

    const body = try body_writer.toOwnedSlice();
    return .{
        .status = @intFromEnum(result.status),
        .body = body,
        .owned_body = body,
    };
}

fn buildHttpUrl(allocator: std.mem.Allocator, base_url: []const u8, path: []const u8) ![]u8 {
    if (std.mem.startsWith(u8, path, "https://") or std.mem.startsWith(u8, path, "http://")) {
        return allocator.dupe(u8, path);
    }
    if (base_url.len == 0) return error.MissingRemoteUrl;
    if (!(std.mem.startsWith(u8, base_url, "https://") or std.mem.startsWith(u8, base_url, "http://"))) {
        return error.UnsupportedRemoteUrl;
    }

    const base = std.mem.trimEnd(u8, base_url, "/");
    if (path.len == 0) return allocator.dupe(u8, base);
    const normalized_path = if (path[0] == '/') path else try std.fmt.allocPrint(allocator, "/{s}", .{path});
    defer if (normalized_path.ptr != path.ptr) allocator.free(normalized_path);
    return std.fmt.allocPrint(allocator, "{s}{s}", .{ base, normalized_path });
}

fn dupeNormalizedUrlZ(allocator: std.mem.Allocator, url: []const u8) ![:0]u8 {
    if (std.mem.startsWith(u8, url, "libsql://")) {
        return std.fmt.allocPrintSentinel(allocator, "https://{s}", .{url["libsql://".len..]}, 0);
    }
    if (std.mem.startsWith(u8, url, "https://")) return allocator.dupeZ(u8, url);
    if (std.mem.startsWith(u8, url, "http://")) return allocator.dupeZ(u8, url);
    return error.Misuse;
}

fn sliceBytes(slice: c.turso_slice_ref_t) []const u8 {
    if (slice.ptr == null or slice.len == 0) return &.{};
    const ptr: [*]const u8 = @ptrCast(slice.ptr);
    return ptr[0..slice.len];
}

fn isControlFlow(status: c.turso_status_code_t) bool {
    return switch (status) {
        c.TURSO_OK, c.TURSO_DONE, c.TURSO_ROW, c.TURSO_IO => true,
        else => false,
    };
}

fn mapStatus(
    status: c.turso_status_code_t,
    error_ptr: [*c]const u8,
    allocator: std.mem.Allocator,
) err.TursoError {
    return err.mapStatus(status, error_ptr, allocator);
}

test "sync HTTP URL builder accepts absolute request paths" {
    const allocator = std.testing.allocator;
    const url = try buildHttpUrl(allocator, "https://base.example", "http://override.example/sync");
    defer allocator.free(url);
    try std.testing.expectEqualStrings("http://override.example/sync", url);
}

test "sync HTTP URL builder joins base URL and relative paths" {
    const allocator = std.testing.allocator;

    const with_slash = try buildHttpUrl(allocator, "https://base.example/", "/sync");
    defer allocator.free(with_slash);
    try std.testing.expectEqualStrings("https://base.example/sync", with_slash);

    const without_slash = try buildHttpUrl(allocator, "https://base.example", "sync");
    defer allocator.free(without_slash);
    try std.testing.expectEqualStrings("https://base.example/sync", without_slash);
}

test "sync default IO executor is available without caller context" {
    const executor = defaultIoExecutor();
    try std.testing.expect(executor.context == null);
}
