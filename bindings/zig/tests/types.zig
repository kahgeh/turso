const std = @import("std");
const turso = @import("turso");
const support = @import("support.zig");

test "row value kinds and accounting are preserved across statement transitions" {
    const allocator = std.testing.allocator;

    var fixture = try support.openInMemory(allocator);
    defer fixture.deinit();

    var create_stmt = try support.prepare(
        allocator,
        &fixture.conn,
        "CREATE TABLE t(i INTEGER, r REAL, s TEXT, b BLOB, n INTEGER)",
    );
    defer create_stmt.deinit();
    _ = try create_stmt.stmt.execute();

    var insert_stmt = try support.prepare(
        allocator,
        &fixture.conn,
        "INSERT INTO t(i, r, s, b, n) VALUES (42, 3.5, 'hello', x'deadbeef', NULL)",
    );
    defer insert_stmt.deinit();

    try std.testing.expectEqual(@as(u64, 1), try insert_stmt.stmt.execute());
    try std.testing.expectEqual(@as(i64, 1), insert_stmt.stmt.nChange());
    try std.testing.expectEqual(@as(i64, 1), fixture.conn.lastInsertRowId());

    var query_stmt = try support.prepare(allocator, &fixture.conn, "SELECT i, r, s, b, n FROM t");
    defer query_stmt.deinit();

    try std.testing.expectEqual(turso.status.StatusCode.TURSO_ROW, try query_stmt.stmt.step());
    try std.testing.expectEqual(turso.val.ValueKind.integer, query_stmt.stmt.rowValueKind(0));
    try std.testing.expectEqual(@as(i64, 42), query_stmt.stmt.rowValueInt(0));
    try std.testing.expectEqual(turso.val.ValueKind.real, query_stmt.stmt.rowValueKind(1));
    try std.testing.expectApproxEqAbs(@as(f64, 3.5), query_stmt.stmt.rowValueDouble(1), 1e-9);
    try std.testing.expectEqual(turso.val.ValueKind.text, query_stmt.stmt.rowValueKind(2));
    const text_copy = try query_stmt.stmt.rowValueText(2);
    defer allocator.free(text_copy);
    try std.testing.expectEqualStrings("hello", text_copy);
    try std.testing.expectEqual(turso.val.ValueKind.blob, query_stmt.stmt.rowValueKind(3));
    const blob_copy = try query_stmt.stmt.rowValueBlob(3);
    defer allocator.free(blob_copy);
    try std.testing.expectEqualSlices(u8, &.{ 0xde, 0xad, 0xbe, 0xef }, blob_copy);
    try std.testing.expectEqual(turso.val.ValueKind.null, query_stmt.stmt.rowValueKind(4));

    try std.testing.expectEqual(turso.status.StatusCode.TURSO_DONE, try query_stmt.stmt.step());
    try query_stmt.finalize();

    try std.testing.expectEqualStrings("hello", text_copy);
    try std.testing.expectEqualSlices(u8, &.{ 0xde, 0xad, 0xbe, 0xef }, blob_copy);
}
