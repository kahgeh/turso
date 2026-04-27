const std = @import("std");
const turso = @import("turso");

const allocator = std.testing.allocator;
var next_id = std.atomic.Value(u64).init(0);

const Server = struct {
    threaded: std.Io.Threaded,
    child: std.process.Child,
    url: []u8,
    db_path: []u8,

    fn init() !Server {
        const unique = std.testing.random_seed + next_id.fetchAdd(1, .monotonic);
        const port: u16 = @intCast(10_000 + (unique % 50_000));
        const address = try std.fmt.allocPrint(allocator, "127.0.0.1:{d}", .{port});
        defer allocator.free(address);

        const url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}", .{port});
        errdefer allocator.free(url);
        const db_path = try tmpDbPath("sync-server");
        errdefer allocator.free(db_path);

        var threaded: std.Io.Threaded = .init(allocator, .{});
        errdefer threaded.deinit();

        const server_bin = "../../target/debug/tursodb";
        var child = try std.process.spawn(threaded.io(), .{
            .argv = &.{ server_bin, db_path, "--sync-server", address },
            .stdout = .ignore,
            .stderr = .ignore,
        });
        errdefer child.kill(threaded.io());

        var attempt: usize = 0;
        while (attempt < 100) : (attempt += 1) {
            if (httpRequest(.GET, url, null)) |response| {
                allocator.free(response.body);
                break;
            } else |_| {
                try std.Io.sleep(threaded.io(), .fromMilliseconds(50), .awake);
            }
        } else {
            return error.SyncServerNotReady;
        }

        return .{
            .threaded = threaded,
            .child = child,
            .url = url,
            .db_path = db_path,
        };
    }

    fn deinit(self: *Server) void {
        self.child.kill(self.threaded.io());
        self.threaded.deinit();
        allocator.free(self.url);
        allocator.free(self.db_path);
    }

    fn dbSql(self: *Server, sql: []const u8) ![]u8 {
        const body = try pipelineBody(sql);
        defer allocator.free(body);

        const url = try std.fmt.allocPrint(allocator, "{s}/v2/pipeline", .{self.url});
        defer allocator.free(url);

        const response = try httpRequest(.POST, url, body);
        errdefer allocator.free(response.body);
        try std.testing.expect(response.status >= 200 and response.status < 300);
        try std.testing.expect(std.mem.indexOf(u8, response.body, "\"type\":\"ok\"") != null);
        return response.body;
    }

    fn dbUrl(self: *Server) []const u8 {
        return self.url;
    }
};

const HttpResponse = struct {
    status: u16,
    body: []u8,
};

fn httpRequest(method: std.http.Method, url: []const u8, body: ?[]const u8) !HttpResponse {
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    var client: std.http.Client = .{
        .allocator = allocator,
        .io = threaded.io(),
    };
    defer client.deinit();

    var writer: std.Io.Writer.Allocating = .init(allocator);
    errdefer writer.deinit();

    const headers = [_]std.http.Header{
        .{ .name = "content-type", .value = "application/json" },
    };
    const result = try client.fetch(.{
        .location = .{ .url = url },
        .method = method,
        .payload = body,
        .extra_headers = if (body == null) &.{} else &headers,
        .response_writer = &writer.writer,
    });

    return .{
        .status = @intFromEnum(result.status),
        .body = try writer.toOwnedSlice(),
    };
}

fn pipelineBody(sql: []const u8) ![]u8 {
    var writer: std.Io.Writer.Allocating = .init(allocator);
    errdefer writer.deinit();

    try writer.writer.writeAll("{\"requests\":[{\"type\":\"execute\",\"stmt\":{\"sql\":");
    try appendJsonString(&writer.writer, sql);
    try writer.writer.writeAll("}}]}");

    return writer.toOwnedSlice();
}

fn appendJsonString(writer: *std.Io.Writer, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |byte| {
        switch (byte) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(byte),
        }
    }
    try writer.writeByte('"');
}

fn tmpDbPath(comptime name: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, ".zig-cache/tmp/sync-e2e-{s}-{d}-{d}.db", .{
        name,
        std.testing.random_seed,
        next_id.fetchAdd(1, .monotonic),
    });
}

fn expectTextRows(conn: *turso.conn.Connection, sql: []const u8, expected: []const []const u8) !void {
    var result = try conn.query(sql);
    defer result.deinit();

    try std.testing.expectEqual(expected.len, result.rows.len);
    for (expected, 0..) |text, index| {
        try std.testing.expectEqualStrings(text, result.rows[index].values[0].text);
    }
}

fn expectLazyPartialRead(
    comptime name: []const u8,
    rows: usize,
    prefix: i32,
    segment_size: usize,
    prefetch: bool,
    initial_max_bytes: i64,
) !void {
    var server = try Server.init();
    defer server.deinit();

    var body = try server.dbSql("CREATE TABLE t(x)");
    allocator.free(body);

    const insert = try std.fmt.allocPrint(
        allocator,
        "INSERT INTO t SELECT randomblob(1024) FROM generate_series(1, {d})",
        .{rows},
    );
    defer allocator.free(insert);
    body = try server.dbSql(insert);
    allocator.free(body);

    var full_db = try turso.sync.Builder.newRemote(allocator, ":memory:")
        .withRemoteUrl(server.dbUrl())
        .build();
    defer full_db.deinit();

    var full_conn = try full_db.connect();
    defer full_conn.deinit();
    var full_result = try full_conn.query("SELECT LENGTH(x) FROM t LIMIT 1");
    defer full_result.deinit();
    var full_stats = try full_db.stats();
    defer full_stats.deinit();
    try std.testing.expect(full_stats.network_received_bytes > @as(i64, @intCast(rows * 1024)));

    var partial_db = try turso.sync.Builder.newRemote(allocator, ":memory:")
        .withRemoteUrl(server.dbUrl())
        .withPartialSyncOptsExperimental(.{
            .strategy = .{ .prefix = prefix },
            .segment_size = segment_size,
            .prefetch = prefetch,
        })
        .build();
    defer partial_db.deinit();

    var partial_conn = try partial_db.connect();
    defer partial_conn.deinit();

    var first_page = try partial_conn.query("SELECT LENGTH(x) FROM t LIMIT 1");
    defer first_page.deinit();
    var partial_stats = try partial_db.stats();
    defer partial_stats.deinit();
    try std.testing.expect(partial_stats.network_received_bytes < initial_max_bytes);

    var sum = try partial_conn.query("SELECT SUM(LENGTH(x)) FROM t");
    defer sum.deinit();
    try std.testing.expectEqual(@as(i64, @intCast(rows * 1024)), sum.rows[0].values[0].integer);

    var final_stats = try partial_db.stats();
    defer final_stats.deinit();
    try std.testing.expect(final_stats.network_received_bytes > @as(i64, @intCast(rows * 1024)));

    _ = name;
}

test "sync e2e bootstrap" {
    var server = try Server.init();
    defer server.deinit();

    var body = try server.dbSql("CREATE TABLE t(x)");
    allocator.free(body);
    body = try server.dbSql("INSERT INTO t VALUES ('hello'), ('turso'), ('sync')");
    allocator.free(body);

    var db = try turso.sync.Builder.newRemote(allocator, ":memory:")
        .withRemoteUrl(server.dbUrl())
        .build();
    defer db.deinit();

    var conn = try db.connect();
    defer conn.deinit();

    try expectTextRows(&conn, "SELECT x FROM t ORDER BY rowid", &.{ "hello", "turso", "sync" });
}

test "sync e2e bootstrap persistence" {
    var server = try Server.init();
    defer server.deinit();

    var body = try server.dbSql("CREATE TABLE t(x)");
    allocator.free(body);
    body = try server.dbSql("INSERT INTO t VALUES ('hello'), ('turso'), ('sync')");
    allocator.free(body);

    const db_path = try tmpDbPath("bootstrap-persistence");
    defer allocator.free(db_path);

    var db = try turso.sync.Builder.newRemote(allocator, db_path)
        .withRemoteUrl(server.dbUrl())
        .build();
    defer db.deinit();

    var conn = try db.connect();
    defer conn.deinit();

    try expectTextRows(&conn, "SELECT x FROM t ORDER BY rowid", &.{ "hello", "turso", "sync" });
}

test "sync e2e config persistence" {
    var server = try Server.init();
    defer server.deinit();

    var body = try server.dbSql("CREATE TABLE t(x)");
    allocator.free(body);
    body = try server.dbSql("INSERT INTO t VALUES (42)");
    allocator.free(body);

    const db_path = try tmpDbPath("config-persistence");
    defer allocator.free(db_path);

    {
        var db = try turso.sync.Builder.newRemote(allocator, db_path)
            .withRemoteUrl(server.dbUrl())
            .build();
        defer db.deinit();

        var conn = try db.connect();
        defer conn.deinit();

        var result = try conn.query("SELECT x FROM t");
        defer result.deinit();
        try std.testing.expectEqual(@as(i64, 42), result.rows[0].values[0].integer);
    }

    body = try server.dbSql("INSERT INTO t VALUES (41)");
    allocator.free(body);

    {
        var db = try turso.sync.Builder.newRemote(allocator, db_path).build();
        defer db.deinit();

        _ = try db.pull();

        var conn = try db.connect();
        defer conn.deinit();

        var result = try conn.query("SELECT x FROM t ORDER BY rowid");
        defer result.deinit();
        try std.testing.expectEqual(@as(i64, 42), result.rows[0].values[0].integer);
        try std.testing.expectEqual(@as(i64, 41), result.rows[1].values[0].integer);
    }
}

test "sync e2e pull" {
    var server = try Server.init();
    defer server.deinit();

    var body = try server.dbSql("CREATE TABLE t(x)");
    allocator.free(body);
    body = try server.dbSql("INSERT INTO t VALUES ('hello'), ('turso'), ('sync')");
    allocator.free(body);

    var db = try turso.sync.Builder.newRemote(allocator, ":memory:")
        .withRemoteUrl(server.dbUrl())
        .build();
    defer db.deinit();

    var conn = try db.connect();
    defer conn.deinit();

    try expectTextRows(&conn, "SELECT x FROM t ORDER BY rowid", &.{ "hello", "turso", "sync" });

    body = try server.dbSql("INSERT INTO t VALUES ('pull works')");
    allocator.free(body);

    try expectTextRows(&conn, "SELECT x FROM t ORDER BY rowid", &.{ "hello", "turso", "sync" });
    try std.testing.expect(try db.pull());
    try expectTextRows(&conn, "SELECT x FROM t ORDER BY rowid", &.{ "hello", "turso", "sync", "pull works" });
}

test "sync e2e push" {
    var server = try Server.init();
    defer server.deinit();

    var body = try server.dbSql("CREATE TABLE t(x)");
    allocator.free(body);
    body = try server.dbSql("INSERT INTO t VALUES ('hello'), ('turso'), ('sync')");
    allocator.free(body);

    var db = try turso.sync.Builder.newRemote(allocator, ":memory:")
        .withRemoteUrl(server.dbUrl())
        .build();
    defer db.deinit();

    var conn = try db.connect();
    defer conn.deinit();

    _ = try conn.execute("INSERT INTO t VALUES ('push works')");

    body = try server.dbSql("SELECT x FROM t ORDER BY rowid");
    defer allocator.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "push works") == null);

    try db.push();

    const pushed = try server.dbSql("SELECT x FROM t ORDER BY rowid");
    defer allocator.free(pushed);
    try std.testing.expect(std.mem.indexOf(u8, pushed, "push works") != null);
}

test "sync e2e checkpoint" {
    var server = try Server.init();
    defer server.deinit();

    var db = try turso.sync.Builder.newRemote(allocator, ":memory:")
        .withRemoteUrl(server.dbUrl())
        .build();
    defer db.deinit();

    var conn = try db.connect();
    defer conn.deinit();

    _ = try conn.execute("CREATE TABLE t(x)");
    for (0..1024) |i| {
        const sql = try std.fmt.allocPrint(allocator, "INSERT INTO t VALUES ({d})", .{i});
        defer allocator.free(sql);
        _ = try conn.execute(sql);
    }

    var before = try db.stats();
    defer before.deinit();
    try std.testing.expect(before.main_wal_size > 1024 * 1024);
    try db.checkpoint();
    var after = try db.stats();
    defer after.deinit();
    try std.testing.expect(after.main_wal_size < 8 * 1024);
}

test "sync e2e partial prefix bootstrap" {
    try expectLazyPartialRead("partial-prefix", 512, 128 * 1024, 128 * 1024, false, 256 * (1024 + 10));
}

test "sync e2e partial segment size" {
    try expectLazyPartialRead("partial-segment-size", 256, 128 * 1024, 4 * 1024, false, 128 * 1024 * 3 / 2);
}

test "sync e2e partial prefetch" {
    try expectLazyPartialRead("partial-prefetch", 512, 128 * 1024, 128 * 1024, true, 400 * (1024 + 10));
}
