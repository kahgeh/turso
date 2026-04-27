const std = @import("std");
const turso = @import("turso");
const support = @import("support.zig");

test "prepareFirst iterates through multiple statements" {
    const allocator = std.testing.allocator;

    var fixture = try support.openInMemory(allocator);
    defer fixture.deinit();

    const sql =
        "CREATE TABLE t(a INTEGER); " ++
        "INSERT INTO t(a) VALUES (1), (2); " ++
        "SELECT a FROM t ORDER BY a;   ";

    var start: usize = 0;
    var selected_values = std.array_list.Managed(i64).init(allocator);
    defer selected_values.deinit();
    var statement_count: usize = 0;

    while (start < sql.len) {
        const result = try fixture.conn.prepareFirstValue(sql[start..]);
        if (result.statement == null) {
            const rest = sql[start..];
            const trimmed_len = std.mem.trim(u8, rest, " \t\r\n").len;
            try std.testing.expectEqual(@as(usize, 0), trimmed_len);
            break;
        }

        try std.testing.expect(result.tail_idx > 0);
        statement_count += 1;

        var stmt = result.statement.?;
        defer {
            stmt.finalize() catch {};
            stmt.deinit();
        }

        if (stmt.columnCount() == 0) {
            _ = try stmt.execute();
        } else {
            while (true) {
                const step_status = try stmt.step();
                switch (step_status) {
                    .TURSO_ROW => try selected_values.append(stmt.rowValueInt(0)),
                    .TURSO_DONE => break,
                    else => return error.TestUnexpectedResult,
                }
            }
        }

        start += result.tail_idx;
    }

    try std.testing.expectEqual(@as(usize, 3), statement_count);
    try std.testing.expectEqual(@as(usize, 2), selected_values.items.len);
    try std.testing.expectEqual(@as(i64, 1), selected_values.items[0]);
    try std.testing.expectEqual(@as(i64, 2), selected_values.items[1]);

    const empty_result = try fixture.conn.prepareFirstValue("   ");
    try std.testing.expect(empty_result.statement == null);
    try std.testing.expectEqual(@as(usize, 0), empty_result.tail_idx);
}
