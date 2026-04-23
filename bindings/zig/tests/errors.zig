const std = @import("std");
const support = @import("support.zig");

test "closed connections and deinitialized statements report misuse" {
    const allocator = std.testing.allocator;

    var fixture = try support.openInMemory(allocator);
    defer fixture.deinit();

    var create_stmt = try support.prepare(allocator, fixture.conn, "CREATE TABLE t(a INTEGER, b INTEGER, c INTEGER)");
    defer create_stmt.deinit();
    _ = try create_stmt.stmt.execute();

    var stmt = try support.prepare(allocator, fixture.conn, "INSERT INTO t(a, b, c) VALUES (?1, ?2, ?3)");
    defer stmt.deinit();

    try std.testing.expectEqual(@as(i64, 3), stmt.stmt.parametersCount());
    try std.testing.expectError(error.Misuse, stmt.stmt.bindInt(4, 1));

    stmt.stmt.deinit();
    try std.testing.expectError(error.Misuse, stmt.stmt.execute());

    fixture.conn.deinit();
    try std.testing.expectError(error.Misuse, fixture.conn.prepareSingle("SELECT 1"));

    // The fixture cleanup path tolerates already-deinitialized handles.
}

test "finalized statements remain invalid for further execution" {
    const allocator = std.testing.allocator;

    var fixture = try support.openInMemory(allocator);
    defer fixture.deinit();

    var create_stmt = try support.prepare(allocator, fixture.conn, "CREATE TABLE t(a INTEGER)");
    defer create_stmt.deinit();
    _ = try create_stmt.stmt.execute();

    var stmt = try support.prepare(allocator, fixture.conn, "INSERT INTO t(a) VALUES (1)");
    defer stmt.deinit();

    _ = try stmt.stmt.execute();
    try stmt.finalize();
    try std.testing.expectError(error.Misuse, stmt.stmt.execute());
}
