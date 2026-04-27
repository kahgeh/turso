const std = @import("std");
const turso = @import("turso");

const worker_count = 8;
const max_attempts = 100;

const WorkerResult = struct {
    value: i64 = 0,
    err: ?anyerror = null,
};

fn isRetryable(err: anyerror) bool {
    return switch (err) {
        error.Busy, error.BusySnapshot, error.Generic => true,
        else => false,
    };
}

fn rollbackIfNeeded(conn: *turso.conn.Connection) void {
    _ = conn.execute("ROLLBACK") catch {};
}

fn runConcurrentInsert(
    db: *turso.db.Database,
    ready: *std.atomic.Value(usize),
    result: *WorkerResult,
    worker_id: usize,
) void {
    var conn = db.connect() catch |connect_err| {
        result.err = connect_err;
        return;
    };
    defer conn.deinit();

    var insert_buf: [96]u8 = undefined;
    const insert_sql = std.fmt.bufPrint(
        &insert_buf,
        "INSERT INTO hits(val) VALUES ({d})",
        .{@as(i64, @intCast(worker_id + 1))},
    ) catch unreachable;

    for (0..max_attempts) |_| {
        _ = conn.execute("BEGIN CONCURRENT") catch |begin_err| {
            if (isRetryable(begin_err)) {
                _ = std.Thread.yield() catch {};
                continue;
            }
            result.err = begin_err;
            return;
        };

        _ = ready.fetchAdd(1, .seq_cst);
        while (ready.load(.seq_cst) < worker_count) {
            _ = std.Thread.yield() catch {};
        }

        _ = conn.execute(insert_sql) catch |insert_err| {
            rollbackIfNeeded(&conn);
            if (isRetryable(insert_err)) {
                _ = std.Thread.yield() catch {};
                continue;
            }
            result.err = insert_err;
            return;
        };

        _ = conn.execute("COMMIT") catch |commit_err| {
            rollbackIfNeeded(&conn);
            if (isRetryable(commit_err)) {
                _ = std.Thread.yield() catch {};
                continue;
            }
            result.err = commit_err;
            return;
        };

        result.value = @intCast(worker_id + 1);
        return;
    }

    result.err = error.Busy;
}

test "mvcc begin concurrent allows multiple writer connections to commit" {
    const allocator = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const db_path = try std.fmt.allocPrint(
        allocator,
        ".zig-cache/tmp/{s}/mvcc-concurrent-writes.db",
        .{tmp_dir.sub_path},
    );
    defer allocator.free(db_path);

    var db = try turso.Builder
        .newLocal(std.heap.smp_allocator, db_path)
        .build();
    defer db.deinit();

    var setup_conn = try db.connect();
    defer setup_conn.deinit();

    var journal_mode = try setup_conn.query("PRAGMA journal_mode = 'mvcc'");
    defer journal_mode.deinit();
    try std.testing.expectEqual(@as(usize, 1), journal_mode.rows.len);
    try std.testing.expectEqualStrings("mvcc", journal_mode.rows[0].values[0].text);

    _ = try setup_conn.execute("CREATE TABLE hits(val INTEGER)");

    var ready = std.atomic.Value(usize).init(0);
    var results = [_]WorkerResult{.{}} ** worker_count;
    var threads: [worker_count]std.Thread = undefined;

    for (&threads, 0..) |*thread, index| {
        thread.* = try std.Thread.spawn(
            .{},
            runConcurrentInsert,
            .{ &db, &ready, &results[index], index },
        );
    }

    for (&threads) |*thread| {
        thread.join();
    }

    var sum: i64 = 0;
    for (results) |result| {
        if (result.err) |worker_err| {
            return worker_err;
        }
        sum += result.value;
    }

    try std.testing.expectEqual(@as(i64, 36), sum);

    var count = try setup_conn.query("SELECT COUNT(*), SUM(val) FROM hits");
    defer count.deinit();

    try std.testing.expectEqual(@as(usize, 1), count.rows.len);
    try std.testing.expectEqual(@as(i64, worker_count), count.rows[0].values[0].integer);
    try std.testing.expectEqual(@as(i64, 36), count.rows[0].values[1].integer);
}
