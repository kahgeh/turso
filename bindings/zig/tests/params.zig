const std = @import("std");
const turso = @import("turso");
const support = @import("support.zig");

test "positional and named parameters round-trip values" {
    const allocator = std.testing.allocator;

    var fixture = try support.openInMemory(allocator);
    defer fixture.deinit();

    var create_stmt = try support.prepare(
        allocator,
        &fixture.conn,
        "CREATE TABLE t(i INTEGER, r REAL, s TEXT, b BLOB, n INTEGER)",
    );
    defer create_stmt.deinit();
    _ = try create_stmt.stmt.execute(.{});

    var positional_stmt = try support.prepare(
        allocator,
        &fixture.conn,
        "INSERT INTO t(i, r, s, b, n) VALUES (?1, ?2, ?3, ?4, ?5)",
    );
    defer positional_stmt.deinit();

    try std.testing.expectEqual(@as(i64, 5), positional_stmt.stmt.parametersCount());
    try positional_stmt.stmt.bindInt(1, 42);
    try positional_stmt.stmt.bindDouble(2, 3.14);
    try positional_stmt.stmt.bindText(3, "hello");
    try positional_stmt.stmt.bindBlob(4, &.{ 0xde, 0xad, 0xbe, 0xef });
    try positional_stmt.stmt.bindNull(5);
    try std.testing.expectEqual(@as(u64, 1), try positional_stmt.stmt.execute(.{}));

    var named_stmt = try support.prepare(
        allocator,
        &fixture.conn,
        "INSERT INTO t(i, r, s, b, n) VALUES (:i, :r, :s, :b, :n)",
    );
    defer named_stmt.deinit();

    try std.testing.expectEqual(@as(i64, 5), named_stmt.stmt.parametersCount());
    const pos_i = (try named_stmt.stmt.namedPosition(":i")).?;
    const pos_r = (try named_stmt.stmt.namedPosition(":r")).?;
    const pos_s = (try named_stmt.stmt.namedPosition(":s")).?;
    const pos_b = (try named_stmt.stmt.namedPosition(":b")).?;
    const pos_n = (try named_stmt.stmt.namedPosition(":n")).?;

    try std.testing.expectEqual(@as(usize, 1), pos_i);
    try std.testing.expectEqual(@as(usize, 2), pos_r);
    try std.testing.expectEqual(@as(usize, 3), pos_s);
    try std.testing.expectEqual(@as(usize, 4), pos_b);
    try std.testing.expectEqual(@as(usize, 5), pos_n);
    try std.testing.expectEqual(null, try named_stmt.stmt.namedPosition(":missing"));

    var failing_allocator = std.testing.FailingAllocator.init(allocator, .{ .fail_index = 0 });
    var oom_lookup_stmt = turso.stmt.Statement{
        .ptr = named_stmt.stmt.ptr,
        .allocator = failing_allocator.allocator(),
    };
    try std.testing.expectError(error.OutOfMemory, oom_lookup_stmt.namedPosition(":i"));

    try named_stmt.stmt.bindInt(pos_i, 7);
    try named_stmt.stmt.bindDouble(pos_r, -1.5);
    try named_stmt.stmt.bindText(pos_s, "world");
    try named_stmt.stmt.bindBlob(pos_b, &.{});
    try named_stmt.stmt.bindNull(pos_n);
    try std.testing.expectEqual(@as(u64, 1), try named_stmt.stmt.execute(.{}));

    var query_stmt = try support.prepare(
        allocator,
        &fixture.conn,
        "SELECT i, r, s, b, n FROM t ORDER BY rowid",
    );
    defer query_stmt.deinit();

    try std.testing.expectEqual(turso.status.StatusCode.TURSO_ROW, try query_stmt.stmt.step());
    try std.testing.expectEqual(turso.val.ValueKind.integer, query_stmt.stmt.rowValueKind(0));
    try std.testing.expectEqual(@as(i64, 42), query_stmt.stmt.rowValueInt(0));
    try std.testing.expectEqual(turso.val.ValueKind.real, query_stmt.stmt.rowValueKind(1));
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), query_stmt.stmt.rowValueDouble(1), 1e-9);
    try std.testing.expectEqual(turso.val.ValueKind.text, query_stmt.stmt.rowValueKind(2));
    const first_text = try query_stmt.stmt.rowValueText(2);
    defer allocator.free(first_text);
    try std.testing.expectEqualStrings("hello", first_text);
    try std.testing.expectEqual(turso.val.ValueKind.blob, query_stmt.stmt.rowValueKind(3));
    const first_blob = try query_stmt.stmt.rowValueBlob(3);
    defer allocator.free(first_blob);
    try std.testing.expectEqualSlices(u8, &.{ 0xde, 0xad, 0xbe, 0xef }, first_blob);
    try std.testing.expectEqual(turso.val.ValueKind.null, query_stmt.stmt.rowValueKind(4));

    try std.testing.expectEqual(turso.status.StatusCode.TURSO_ROW, try query_stmt.stmt.step());
    try std.testing.expectEqual(@as(i64, 7), query_stmt.stmt.rowValueInt(0));
    try std.testing.expectApproxEqAbs(@as(f64, -1.5), query_stmt.stmt.rowValueDouble(1), 1e-9);
    const second_text = try query_stmt.stmt.rowValueText(2);
    defer allocator.free(second_text);
    try std.testing.expectEqualStrings("world", second_text);
    try std.testing.expectEqual(turso.val.ValueKind.blob, query_stmt.stmt.rowValueKind(3));
    const second_blob = try query_stmt.stmt.rowValueBlob(3);
    defer allocator.free(second_blob);
    try std.testing.expectEqual(@as(usize, 0), second_blob.len);
    try std.testing.expectEqual(turso.val.ValueKind.null, query_stmt.stmt.rowValueKind(4));

    try std.testing.expectEqual(turso.status.StatusCode.TURSO_DONE, try query_stmt.stmt.step());
}
