const std = @import("std");
const turso = @import("turso");

const Workload = enum {
    open_database,
    open_close,
    prepare_step,
    insert_txn_execute,
    insert_txn_step,
    point_select,
    scan_borrowed,
    scan_owned,
    query_collect,

    fn parse(value: []const u8) !Workload {
        if (std.mem.eql(u8, value, "open_database")) return .open_database;
        if (std.mem.eql(u8, value, "open_close")) return .open_close;
        if (std.mem.eql(u8, value, "prepare_step")) return .prepare_step;
        if (std.mem.eql(u8, value, "insert_txn")) return .insert_txn_execute;
        if (std.mem.eql(u8, value, "insert_txn_execute")) return .insert_txn_execute;
        if (std.mem.eql(u8, value, "insert_txn_step")) return .insert_txn_step;
        if (std.mem.eql(u8, value, "point_select")) return .point_select;
        if (std.mem.eql(u8, value, "scan_borrowed")) return .scan_borrowed;
        if (std.mem.eql(u8, value, "scan_owned")) return .scan_owned;
        if (std.mem.eql(u8, value, "query_collect")) return .query_collect;
        return error.UnknownWorkload;
    }

    fn name(self: Workload) []const u8 {
        return switch (self) {
            .open_database => "open_database",
            .open_close => "open_close",
            .prepare_step => "prepare_step",
            .insert_txn_execute => "insert_txn_execute",
            .insert_txn_step => "insert_txn_step",
            .point_select => "point_select",
            .scan_borrowed => "scan_borrowed",
            .scan_owned => "scan_owned",
            .query_collect => "query_collect",
        };
    }
};

const Args = struct {
    workload: Workload = .point_select,
    rows: usize = 10_000,
    iters: usize = 5,

    fn parse(argv: []const [:0]const u8) !Args {
        var index: usize = 1;

        var parsed: Args = .{};
        while (index < argv.len) {
            const arg = argv[index];
            index += 1;
            if (std.mem.eql(u8, arg, "--workload")) {
                if (index >= argv.len) return error.MissingArgument;
                parsed.workload = try Workload.parse(argv[index]);
                index += 1;
            } else if (std.mem.eql(u8, arg, "--rows")) {
                if (index >= argv.len) return error.MissingArgument;
                parsed.rows = try std.fmt.parseInt(usize, argv[index], 10);
                index += 1;
            } else if (std.mem.eql(u8, arg, "--iters")) {
                if (index >= argv.len) return error.MissingArgument;
                parsed.iters = try std.fmt.parseInt(usize, argv[index], 10);
                index += 1;
            } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
                printHelp();
                std.process.exit(0);
            } else {
                return error.UnknownArgument;
            }
        }
        return parsed;
    }
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const argv = try init.minimal.args.toSlice(allocator);

    const args = Args.parse(argv) catch |parse_err| {
        std.debug.print("{s}\n", .{@errorName(parse_err)});
        printHelp();
        std.process.exit(2);
    };

    const result = switch (args.workload) {
        .open_database => try openDatabase(allocator, init.io, args.rows, args.iters),
        .open_close => try openClose(allocator, init.io, args.rows, args.iters),
        .prepare_step => try prepareStep(allocator, init.io, args.rows, args.iters),
        .insert_txn_execute => try insertTxnExecute(allocator, init.io, args.rows, args.iters),
        .insert_txn_step => try insertTxnStep(allocator, init.io, args.rows, args.iters),
        .point_select => try pointSelect(allocator, init.io, args.rows, args.iters),
        .scan_borrowed => try scanBorrowed(allocator, init.io, args.rows, args.iters),
        .scan_owned => try scanOwned(allocator, init.io, args.rows, args.iters),
        .query_collect => try queryCollect(allocator, init.io, args.rows, args.iters),
    };
    printResult("zig", args.workload, args.rows, args.iters, result.elapsed_ms, result.ops);
}

fn printHelp() void {
    std.debug.print(
        "usage: binding-bench-zig [--workload open_database|open_close|prepare_step|insert_txn_execute|insert_txn_step|point_select|scan_borrowed|scan_owned|query_collect] [--rows N] [--iters N]\n",
        .{},
    );
}

const BenchResult = struct {
    elapsed_ms: f64,
    ops: usize,
};

fn printResult(
    binding: []const u8,
    workload: Workload,
    rows: usize,
    iters: usize,
    elapsed_ms: f64,
    ops: usize,
) void {
    const ops_per_sec = if (elapsed_ms > 0) @as(f64, @floatFromInt(ops)) / (elapsed_ms / 1000.0) else 0;
    std.debug.print(
        "{{\"binding\":\"{s}\",\"workload\":\"{s}\",\"rows\":{d},\"iters\":{d},\"elapsed_ms\":{d:.3},\"ops\":{d},\"ops_per_sec\":{d:.3}}}\n",
        .{ binding, workload.name(), rows, iters, elapsed_ms, ops, ops_per_sec },
    );
}

fn nowNs(io: std.Io) i96 {
    return std.Io.Clock.awake.now(io).nanoseconds;
}

fn elapsedMs(io: std.Io, start: i96) f64 {
    return @as(f64, @floatFromInt(nowNs(io) - start)) / @as(f64, @floatFromInt(std.time.ns_per_ms));
}

fn openClose(allocator: std.mem.Allocator, io: std.Io, rows: usize, iters: usize) !BenchResult {
    const reps = @max(rows * iters, 1);
    const start = nowNs(io);
    for (0..reps) |_| {
        var db = try turso.Builder.newLocal(allocator, ":memory:").build();
        var conn = try db.connect();
        conn.deinit();
        db.deinit();
    }
    return .{ .elapsed_ms = elapsedMs(io, start), .ops = reps };
}

fn openDatabase(allocator: std.mem.Allocator, io: std.Io, rows: usize, iters: usize) !BenchResult {
    const reps = @max(rows * iters, 1);
    const start = nowNs(io);
    for (0..reps) |_| {
        var db = try turso.Builder.newLocal(allocator, ":memory:").build();
        db.deinit();
    }
    return .{ .elapsed_ms = elapsedMs(io, start), .ops = reps };
}

fn prepareStep(allocator: std.mem.Allocator, io: std.Io, rows: usize, iters: usize) !BenchResult {
    const reps = @max(rows * iters, 1);
    var db = try turso.Builder.newLocal(allocator, ":memory:").build();
    defer db.deinit();
    var conn = try db.connect();
    defer conn.deinit();

    const start = nowNs(io);
    for (0..reps) |_| {
        var stmt = try conn.prepareSingle("SELECT 1");
        if (try stmt.step() != .TURSO_ROW) {
            stmt.finalize() catch {};
            stmt.deinit();
            return error.UnexpectedStatus;
        }
        if (try stmt.step() != .TURSO_DONE) {
            stmt.finalize() catch {};
            stmt.deinit();
            return error.UnexpectedStatus;
        }
        stmt.finalize() catch {};
        stmt.deinit();
    }
    return .{ .elapsed_ms = elapsedMs(io, start), .ops = reps };
}

fn insertTxnExecute(allocator: std.mem.Allocator, io: std.Io, rows: usize, iters: usize) !BenchResult {
    var db = try turso.Builder.newLocal(allocator, ":memory:").build();
    defer db.deinit();
    var conn = try db.connect();
    defer conn.deinit();
    _ = try conn.execute("CREATE TABLE t(id INTEGER PRIMARY KEY, value TEXT)");

    var inserted: usize = 0;
    const start = nowNs(io);
    for (0..iters) |iter| {
        _ = try conn.execute("BEGIN");
        var stmt = try conn.prepareSingle("INSERT INTO t(id, value) VALUES (?1, ?2)");
        errdefer {
            stmt.finalize() catch {};
            stmt.deinit();
        }
        for (0..rows) |row| {
            _ = try stmt.execute(.{ @as(i64, @intCast(iter * rows + row)), "payload" });
            inserted += 1;
        }
        try stmt.finalize();
        stmt.deinit();
        _ = try conn.execute("COMMIT");
    }
    return .{ .elapsed_ms = elapsedMs(io, start), .ops = inserted };
}

fn insertTxnStep(allocator: std.mem.Allocator, io: std.Io, rows: usize, iters: usize) !BenchResult {
    var db = try turso.Builder.newLocal(allocator, ":memory:").build();
    defer db.deinit();
    var conn = try db.connect();
    defer conn.deinit();
    _ = try conn.execute("CREATE TABLE t(id INTEGER PRIMARY KEY, value TEXT)");

    var inserted: usize = 0;
    const start = nowNs(io);
    for (0..iters) |iter| {
        _ = try conn.execute("BEGIN");
        var stmt = try conn.prepareSingle("INSERT INTO t(id, value) VALUES (?1, ?2)");
        errdefer {
            stmt.finalize() catch {};
            stmt.deinit();
        }
        for (0..rows) |row| {
            try stmt.reset();
            try stmt.bindInt(1, @intCast(iter * rows + row));
            try stmt.bindText(2, "payload");
            if (try stmt.step() != .TURSO_DONE) return error.UnexpectedStatus;
            inserted += 1;
        }
        try stmt.finalize();
        stmt.deinit();
        _ = try conn.execute("COMMIT");
    }
    return .{ .elapsed_ms = elapsedMs(io, start), .ops = inserted };
}

fn pointSelect(allocator: std.mem.Allocator, io: std.Io, rows: usize, iters: usize) !BenchResult {
    var db = try turso.Builder.newLocal(allocator, ":memory:").build();
    defer db.deinit();
    var conn = try db.connect();
    defer conn.deinit();
    try loadRows(&conn, rows);

    var found: usize = 0;
    const start = nowNs(io);
    var stmt = try conn.prepareSingle("SELECT value FROM t WHERE id = ?1");
    defer {
        stmt.finalize() catch {};
        stmt.deinit();
    }
    for (0..iters) |_| {
        for (0..rows) |row| {
            try stmt.reset();
            try stmt.bindInt(1, @intCast(row));
            if (try stmt.step() == .TURSO_ROW) {
                const value = try stmt.rowValueText(0);
                defer allocator.free(value);
                std.mem.doNotOptimizeAway(value.len);
                found += 1;
            }
        }
    }
    return .{ .elapsed_ms = elapsedMs(io, start), .ops = found };
}

fn scanBorrowed(allocator: std.mem.Allocator, io: std.Io, rows: usize, iters: usize) !BenchResult {
    var db = try turso.Builder.newLocal(allocator, ":memory:").build();
    defer db.deinit();
    var conn = try db.connect();
    defer conn.deinit();
    try loadRows(&conn, rows);

    var scanned: usize = 0;
    var checksum: i64 = 0;
    const start = nowNs(io);
    for (0..iters) |_| {
        var stmt = try conn.prepareSingle("SELECT id FROM t");
        while (try stmt.step() == .TURSO_ROW) {
            checksum +%= try stmt.rowValueIntChecked(0);
            scanned += 1;
        }
        stmt.finalize() catch {};
        stmt.deinit();
    }
    std.mem.doNotOptimizeAway(checksum);
    return .{ .elapsed_ms = elapsedMs(io, start), .ops = scanned };
}

fn scanOwned(allocator: std.mem.Allocator, io: std.Io, rows: usize, iters: usize) !BenchResult {
    var db = try turso.Builder.newLocal(allocator, ":memory:").build();
    defer db.deinit();
    var conn = try db.connect();
    defer conn.deinit();
    try loadRows(&conn, rows);

    var scanned: usize = 0;
    var checksum: i64 = 0;
    const start = nowNs(io);
    for (0..iters) |_| {
        var stmt = try conn.prepareSingle("SELECT id, value FROM t");
        while (try stmt.step() == .TURSO_ROW) {
            var id = try stmt.rowValue(0);
            var value = try stmt.rowValue(1);
            if (id == .integer) {
                checksum +%= id.integer;
                scanned += 1;
            }
            std.mem.doNotOptimizeAway(value);
            id.deinit(allocator);
            value.deinit(allocator);
        }
        stmt.finalize() catch {};
        stmt.deinit();
    }
    std.mem.doNotOptimizeAway(checksum);
    return .{ .elapsed_ms = elapsedMs(io, start), .ops = scanned };
}

fn queryCollect(allocator: std.mem.Allocator, io: std.Io, rows: usize, iters: usize) !BenchResult {
    var db = try turso.Builder.newLocal(allocator, ":memory:").build();
    defer db.deinit();
    var conn = try db.connect();
    defer conn.deinit();
    try loadRows(&conn, rows);

    var scanned: usize = 0;
    var checksum: i64 = 0;
    const start = nowNs(io);
    for (0..iters) |_| {
        var result = try conn.query("SELECT id, value FROM t");
        for (result.rows) |row| {
            if (row.values[0] == .integer) {
                checksum +%= row.values[0].integer;
                scanned += 1;
            }
        }
        result.deinit();
    }
    std.mem.doNotOptimizeAway(checksum);
    return .{ .elapsed_ms = elapsedMs(io, start), .ops = scanned };
}

fn loadRows(conn: *turso.Connection, rows: usize) !void {
    _ = try conn.execute("CREATE TABLE t(id INTEGER PRIMARY KEY, value TEXT)");
    _ = try conn.execute("BEGIN");
    var stmt = try conn.prepareSingle("INSERT INTO t(id, value) VALUES (?1, ?2)");
    defer {
        stmt.finalize() catch {};
        stmt.deinit();
    }
    for (0..rows) |row| {
        try stmt.reset();
        try stmt.bindInt(1, @intCast(row));
        try stmt.bindText(2, "payload");
        if (try stmt.step() != .TURSO_DONE) return error.UnexpectedStatus;
    }
    _ = try conn.execute("COMMIT");
}
