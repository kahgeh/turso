const std = @import("std");
const turso = @import("turso");

const Workload = enum {
    open_close,
    insert_txn,
    point_select,
    scan,

    fn parse(value: []const u8) !Workload {
        if (std.mem.eql(u8, value, "open_close")) return .open_close;
        if (std.mem.eql(u8, value, "insert_txn")) return .insert_txn;
        if (std.mem.eql(u8, value, "point_select")) return .point_select;
        if (std.mem.eql(u8, value, "scan")) return .scan;
        return error.UnknownWorkload;
    }

    fn name(self: Workload) []const u8 {
        return switch (self) {
            .open_close => "open_close",
            .insert_txn => "insert_txn",
            .point_select => "point_select",
            .scan => "scan",
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
        .open_close => try openClose(allocator, init.io, args.rows, args.iters),
        .insert_txn => try insertTxn(allocator, init.io, args.rows, args.iters),
        .point_select => try pointSelect(allocator, init.io, args.rows, args.iters),
        .scan => try scan(allocator, init.io, args.rows, args.iters),
    };
    printResult("zig", args.workload, args.rows, args.iters, result.elapsed_ms, result.ops);
}

fn printHelp() void {
    std.debug.print(
        "usage: binding-bench-zig [--workload open_close|insert_txn|point_select|scan] [--rows N] [--iters N]\n",
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
        defer db.deinit();
        var conn = try db.connect();
        defer conn.deinit();
    }
    return .{ .elapsed_ms = elapsedMs(io, start), .ops = reps };
}

fn insertTxn(allocator: std.mem.Allocator, io: std.Io, rows: usize, iters: usize) !BenchResult {
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
        defer {
            stmt.finalize() catch {};
            stmt.deinit();
        }
        for (0..rows) |row| {
            try stmt.reset();
            try stmt.bindInt(1, @intCast(iter * rows + row));
            try stmt.bindText(2, "payload");
            _ = try stmt.execute();
            inserted += 1;
        }
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

fn scan(allocator: std.mem.Allocator, io: std.Io, rows: usize, iters: usize) !BenchResult {
    var db = try turso.Builder.newLocal(allocator, ":memory:").build();
    defer db.deinit();
    var conn = try db.connect();
    defer conn.deinit();
    try loadRows(&conn, rows);

    var scanned: usize = 0;
    var checksum: i64 = 0;
    const start = nowNs(io);
    for (0..iters) |_| {
        var stream = try conn.rows("SELECT id FROM t");
        defer stream.deinit();
        while (try stream.next()) |row| {
            checksum +%= try row.int(0);
            scanned += 1;
        }
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
        _ = try stmt.execute();
    }
    _ = try conn.execute("COMMIT");
}
