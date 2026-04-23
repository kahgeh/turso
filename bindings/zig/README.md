# Turso Zig Binding

Zig bindings for [TursoDB](https://turso.tech) local database access. This package wraps the `turso_sdk_kit` C ABI and exposes thin Zig modules for database, connection, statement, value, status, and error handling.

## Layout

```text
bindings/zig/
├── build.zig
├── README.md
├── src/
│   ├── root.zig
│   ├── c.zig
│   ├── connection.zig
│   ├── database.zig
│   ├── error.zig
│   ├── statement.zig
│   ├── status.zig
│   └── value.zig
└── tests/
    ├── basic.zig
    ├── metadata.zig
    ├── multi_statement.zig
    ├── params.zig
    └── support.zig
```

## Supported Environment

The binding is validated in this repository on macOS with the local development target. The build links the Rust static archive directly and also links `CoreFoundation`, so other targets may need additional build work before they are supported.

## Native Library

The Zig package consumes the `turso_sdk_kit` static library produced by the Rust workspace.

Build the native library first:

```bash
cargo build --package turso_sdk_kit --lib
```

The current `build.zig` expects the archive at:

```text
../../target/debug/libturso_sdk_kit.a
```

from `bindings/zig/`.

## Usage

The module name is `turso`. Import it from your Zig code and open a database, create a connection, then prepare and execute statements.

```zig
const std = @import("std");
const turso = @import("turso");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var db = turso.db.Database.init(allocator);
    try db.create(&.{ .path = ":memory:" });
    defer db.deinit();

    const conn = try db.connect();
    defer {
        conn.deinit();
        allocator.destroy(conn);
    }

    var create_stmt = try conn.prepareSingle("CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT)");
    defer {
        create_stmt.finalize() catch {};
        create_stmt.deinit();
    }
    _ = try create_stmt.execute();

    var insert_stmt = try conn.prepareSingle("INSERT INTO t(name) VALUES ('"'"'ada'"'"')");
    defer {
        insert_stmt.finalize() catch {};
        insert_stmt.deinit();
    }
    _ = try insert_stmt.execute();

    var query_stmt = try conn.prepareSingle("SELECT id, name FROM t");
    defer {
        query_stmt.finalize() catch {};
        query_stmt.deinit();
    }

    if ((try query_stmt.step()) == turso.status.StatusCode.TURSO_ROW) {
        const id = query_stmt.rowValueInt(0);
        const name = try query_stmt.rowValueText(1);
        defer allocator.free(name);
        std.debug.print("row: {d} {s}\n", .{ id, name });
    }
}
```

## Ownership Rules

- `Database`, `Connection`, and `Statement` handles must be explicitly deinitialized.
- `Connection.close()` and `Statement.finalize()` are separate from `deinit()`.
- Text and blob row values returned by the wrapper are owned copies in Zig memory.
- Metadata strings returned by `columnName()` and `columnDecltype()` are owned copies in Zig memory.
- Strings allocated by Turso are released inside the wrapper with `turso_str_deinit()`.
- `prepareFirst()` can return a null statement when the remaining SQL contains only whitespace or comments.

## Tests

Run the Zig suite through the build system:

```bash
zig build test --summary all
```

The current test matrix covers:

- memory-backed open/create/insert/query
- lifecycle cleanup paths
- positional and named parameters
- column metadata ownership
- multi-statement `prepareFirst()` parsing
- row value kinds and copied TEXT/BLOB values
- row-change and last-insert-rowid accounting
- regression queries for `RETURNING`, joins, subqueries, `ALTER TABLE`, `generate_series`, and JSON helpers
