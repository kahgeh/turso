const std = @import("std");
const turso = @import("turso");
const support = @import("support.zig");

fn openEncrypted(allocator: std.mem.Allocator, path: []const u8, hexkey: []const u8) !turso.db.Database {
    var db = turso.db.Database.init(allocator);
    try db.create(&.{
        .path = path,
        .experimental_features = "encryption",
        .encryption_cipher = "aegis256",
        .encryption_hexkey = hexkey,
    });
    return db;
}

fn expectOpenFailure(allocator: std.mem.Allocator, config: turso.db.DatabaseConfig) !void {
    var db = turso.db.Database.init(allocator);
    defer db.deinit();

    if (db.create(&config)) |_| {
        return error.TestUnexpectedResult;
    } else |_| {
        return;
    }
}

test "encrypted files reopen with the same key" {
    const allocator = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const db_path = try std.fmt.allocPrint(
        allocator,
        ".zig-cache/tmp/{s}/encrypted.db",
        .{tmp_dir.sub_path},
    );
    defer allocator.free(db_path);

    const hexkey = "b1bbfda4f589dc9daaf004fe21111e00dc00c98237102f5c7002a5669fc76327";
    {
        var db = try openEncrypted(allocator, db_path, hexkey);
        defer db.deinit();

        const conn = try db.connect();
        defer {
            conn.deinit();
            allocator.destroy(conn);
        }

        var create_stmt = try support.prepare(allocator, conn, "CREATE TABLE t(value TEXT)");
        defer create_stmt.deinit();
        _ = try create_stmt.stmt.execute();

        var insert_stmt = try support.prepare(allocator, conn, "INSERT INTO t(value) VALUES ('secret')");
        defer insert_stmt.deinit();
        try std.testing.expectEqual(@as(u64, 1), try insert_stmt.stmt.execute());
    }

    {
        var db = try openEncrypted(allocator, db_path, hexkey);
        defer db.deinit();

        const conn = try db.connect();
        defer {
            conn.deinit();
            allocator.destroy(conn);
        }

        var count_stmt = try support.prepare(allocator, conn, "SELECT COUNT(*) FROM t");
        defer count_stmt.deinit();
        try std.testing.expectEqual(turso.status.StatusCode.TURSO_ROW, try count_stmt.stmt.step());
        try std.testing.expectEqual(@as(i64, 1), count_stmt.stmt.rowValueInt(0));
    }
}

test "wrong key and unencrypted reopen fail to open encrypted files" {
    const allocator = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const db_path = try std.fmt.allocPrint(
        allocator,
        ".zig-cache/tmp/{s}/encrypted.db",
        .{tmp_dir.sub_path},
    );
    defer allocator.free(db_path);

    const hexkey = "b1bbfda4f589dc9daaf004fe21111e00dc00c98237102f5c7002a5669fc76327";
    {
        var db = try openEncrypted(allocator, db_path, hexkey);
        defer db.deinit();

        const conn = try db.connect();
        defer {
            conn.deinit();
            allocator.destroy(conn);
        }

        var create_stmt = try support.prepare(allocator, conn, "CREATE TABLE t(value TEXT)");
        defer create_stmt.deinit();
        _ = try create_stmt.stmt.execute();
    }

    try expectOpenFailure(allocator, .{
        .path = db_path,
        .experimental_features = "encryption",
        .encryption_cipher = "aegis256",
        .encryption_hexkey = "aaaaaaa4f589dc9daaf004fe21111e00dc00c98237102f5c7002a5669fc76327",
    });

    try expectOpenFailure(allocator, .{
        .path = db_path,
    });
}
