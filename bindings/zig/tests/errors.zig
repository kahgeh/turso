const std = @import("std");
const turso = @import("turso");
const support = @import("support.zig");

test "closed connections and deinitialized statements report misuse" {
    const allocator = std.testing.allocator;

    var fixture = try support.openInMemory(allocator);
    defer fixture.deinit();

    var create_stmt = try support.prepare(allocator, &fixture.conn, "CREATE TABLE t(a INTEGER, b INTEGER, c INTEGER)");
    defer create_stmt.deinit();
    _ = try create_stmt.stmt.execute();

    var stmt = try support.prepare(allocator, &fixture.conn, "INSERT INTO t(a, b, c) VALUES (?1, ?2, ?3)");
    defer stmt.deinit();

    try std.testing.expectEqual(@as(i64, 3), stmt.stmt.parametersCount());
    try std.testing.expectError(error.Misuse, stmt.stmt.bindInt(4, 1));

    stmt.stmt.deinit();
    try std.testing.expectError(error.Misuse, stmt.stmt.execute());
    try std.testing.expectError(error.Misuse, stmt.stmt.runIO());
    try std.testing.expectError(error.Misuse, stmt.stmt.reset());
    try std.testing.expectError(error.Misuse, stmt.stmt.finalize());
    try std.testing.expectError(error.Misuse, stmt.stmt.bindNull(1));
    try std.testing.expectError(error.Misuse, stmt.stmt.bindInt(1, 1));
    try std.testing.expectError(error.Misuse, stmt.stmt.bindDouble(1, 1.0));
    try std.testing.expectError(error.Misuse, stmt.stmt.bindText(1, "x"));
    try std.testing.expectError(error.Misuse, stmt.stmt.bindBlob(1, &.{1}));
    try std.testing.expectError(error.Misuse, stmt.stmt.rowValueKindChecked(0));
    try std.testing.expectError(error.Misuse, stmt.stmt.rowValueIntChecked(0));
    try std.testing.expectError(error.Misuse, stmt.stmt.rowValueDoubleChecked(0));
    try std.testing.expectError(error.Misuse, stmt.stmt.rowValueText(0));
    try std.testing.expectError(error.Misuse, stmt.stmt.rowValueBlob(0));
    try std.testing.expectError(error.Misuse, stmt.stmt.rowValue(0));
    try std.testing.expectError(error.Misuse, stmt.stmt.columnCountChecked());
    try std.testing.expectError(error.Misuse, stmt.stmt.columnName(0));
    try std.testing.expectError(error.Misuse, stmt.stmt.columnDecltype(0));
    try std.testing.expectError(error.Misuse, stmt.stmt.namedPosition(":i"));
    try std.testing.expectError(error.Misuse, stmt.stmt.parametersCountChecked());
    try std.testing.expectError(error.Misuse, stmt.stmt.nChangeChecked());
    stmt.finalized = true;

    fixture.conn.deinit();
    try std.testing.expectError(error.Misuse, fixture.conn.close());
    try std.testing.expectError(error.Misuse, fixture.conn.prepareSingle("SELECT 1"));
    try std.testing.expectError(error.Misuse, fixture.conn.setBusyTimeout(1));
    try std.testing.expectError(error.Misuse, fixture.conn.getAutocommitChecked());
    try std.testing.expectError(error.Misuse, fixture.conn.lastInsertRowIdChecked());
    fixture.closed = true;

    // The fixture cleanup path tolerates already-deinitialized handles.
}

test "finalized statements remain invalid for further execution" {
    const allocator = std.testing.allocator;

    var fixture = try support.openInMemory(allocator);
    defer fixture.deinit();

    var create_stmt = try support.prepare(allocator, &fixture.conn, "CREATE TABLE t(a INTEGER)");
    defer create_stmt.deinit();
    _ = try create_stmt.stmt.execute();

    var stmt = try support.prepare(allocator, &fixture.conn, "INSERT INTO t(a) VALUES (1)");
    defer stmt.deinit();

    _ = try stmt.stmt.execute();
    try stmt.finalize();
    try std.testing.expectError(error.Misuse, stmt.stmt.execute());
}

test "engine diagnostics expose C error messages" {
    const allocator = std.testing.allocator;

    var fixture = try support.openInMemory(allocator);
    defer fixture.deinit();

    var diagnostic = turso.err.Diagnostic.init(allocator);
    defer diagnostic.deinit();

    try std.testing.expectError(error.Generic, fixture.conn.executeWithDiagnostic("SELEC invalid", &diagnostic));
    try std.testing.expect(diagnostic.message != null);
    try std.testing.expect(diagnostic.message.?.len > 0);
}
