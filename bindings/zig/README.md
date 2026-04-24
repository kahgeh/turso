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
    ├── async_io.zig
    ├── contention.zig
    ├── encryption.zig
    ├── file_backed.zig
    ├── metadata.zig
    ├── multi_statement.zig
    ├── params.zig
    ├── regressions.zig
    ├── support.zig
    ├── types.zig
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
- misuse and lifecycle error paths
- file-backed reopen and duplicate-connection coverage
- encryption reopen and wrong-key coverage
- busy-timeout and concurrent-writer contention coverage
- async `TURSO_IO` retry coverage

## Parity Matrix

The Zig binding is aligned with the low-level coverage in `bindings/go/bindings_db_test.go` and the binding-relevant parts of `bindings/go/driver_db_test.go`. The remaining differences are explicit:

| Area | Zig status | Notes |
| --- | --- | --- |
| Open/create/connect/close lifecycle | Supported | Covered by smoke, file-backed, and error-path tests. |
| Single-statement execution and stepping | Supported | Includes synchronous and async retry coverage. |
| Positional and named parameters | Supported | Includes binding counts and round-trips. |
| Column metadata | Supported | Includes owned-copy behavior. |
| Multi-statement `prepareFirst()` | Supported | Includes trailing SQL and null-statement cases. |
| Row decoding and accounting | Supported | Covers INTEGER, REAL, TEXT, BLOB, NULL, `n_change`, and `lastInsertRowId()`. |
| File-backed reopen and encryption | Supported | Covers reopen with the same key and controlled failure for wrong or missing keys. |
| Busy timeout and contention | Supported | Covers runtime timeout changes and concurrent writer behavior. |
| Async `TURSO_IO` retry | Supported | Exercised through the public execute/step wrappers. |
| DSN parsing and connector options | Not modeled | Zig binds the direct C ABI and does not expose a Go-style connector layer. |
| Default busy-timeout connector tests | Not modeled | There is no Zig connector abstraction to host DSN precedence checks. |
| Higher-level `sql.DB` driver integration | Not modeled | Out of scope for the thin Zig wrapper. |
