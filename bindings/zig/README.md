# Turso Zig Binding

Zig bindings for [TursoDB](https://turso.tech) local database access. This package wraps the `turso_sdk_kit` C ABI and exposes thin Zig modules plus higher-level local-database convenience helpers.

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
    ├── high_level.zig
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

The module name is `turso`. Import it from your Zig code and use the builder for the common local open/connect flow:

```zig
const std = @import("std");
const turso = @import("turso");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var opened = try turso.Builder.newLocal(allocator, ":memory:").connect();
    defer opened.deinit();

    _ = try opened.connection.execute("CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT)");
    _ = try opened.connection.execute("INSERT INTO t(name) VALUES ('ada')");

    var result = try opened.connection.query("SELECT id, name FROM t");
    defer result.deinit();

    std.debug.print("row: {d} {s}\n", .{
        result.rows[0].values[0].integer,
        result.rows[0].values[1].text,
    });
}
```

The lower-level handle API remains available when callers need direct statement binding, stepping, reset, or finalize control:

```zig
const std = @import("std");
const turso = @import("turso");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var db = turso.db.Database.init(allocator);
    try db.create(&.{ .path = ":memory:" });
    defer db.deinit();

    var conn = try db.connectValue();
    defer conn.deinit();

    var create_stmt = try conn.prepareSingleValue("CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT)");
    defer {
        create_stmt.finalize() catch {};
        create_stmt.deinit();
    }
    _ = try create_stmt.execute();

    var insert_stmt = try conn.prepareSingleValue("INSERT INTO t(name) VALUES ('"'"'ada'"'"')");
    defer {
        insert_stmt.finalize() catch {};
        insert_stmt.deinit();
    }
    _ = try insert_stmt.execute();

    var query_stmt = try conn.prepareSingleValue("SELECT id, name FROM t");
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
- Prefer `connectValue()`, `prepareSingleValue()`, and `prepareFirstValue()` for value handles.
- `Connection.close()` and `Statement.finalize()` are separate from `deinit()`.
- Text and blob row values returned by the wrapper are owned copies in Zig memory.
- `Connection.query()` returns owned copied rows and metadata; call `QueryResult.deinit()` to release them.
- `Connection.rows()` streams row views; borrowed text/blob slices are valid until the next step, reset, finalize, or `Rows.deinit()`.
- Metadata strings returned by `columnName()` and `columnDecltype()` are owned copies in Zig memory.
- `Statement.namedPosition()` returns `!?usize`; null means the named parameter is absent.
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
- streaming row iteration with borrowed TEXT/BLOB values
- row-change and last-insert-rowid accounting
- regression queries for `RETURNING`, joins, subqueries, `ALTER TABLE`, `generate_series`, and JSON helpers
- misuse and lifecycle error paths
- file-backed reopen and duplicate-connection coverage
- encryption reopen and wrong-key coverage
- busy-timeout and concurrent-writer contention coverage
- MVCC `BEGIN CONCURRENT` writer coverage
- async `TURSO_IO` retry coverage
- builder, execute/query, execute-batch, and transaction convenience coverage

## Sync Layer

The Zig binding is intentionally local-only for now. The exposed C ABI currently covers local database, connection, and statement handles; it does not expose the Rust sync engine configuration or lifecycle. Zig sync parity should be added as a separate wrapper only after the C ABI has an explicit sync surface to bind.

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
| MVCC concurrent writers | Supported | Covers `PRAGMA journal_mode = 'mvcc'` plus multiple `BEGIN CONCURRENT` writer connections. |
| Async `TURSO_IO` retry | Supported | Exercised through the public execute/step wrappers. |
| Builder-style local construction | Supported | `turso.Builder.newLocal(...).build()` and `.connect()`. |
| Higher-level execute/query helpers | Supported | `Connection.execute()`, `executeBatch()`, and `query()` preserve owned-copy row semantics. |
| Transaction ergonomics | Supported | `Connection.transaction()` with explicit `commit()` / `rollback()`. |
| Rust sync layer | Not modeled | Local-only by design until the C ABI exposes sync primitives. |
| DSN parsing and connector options | Not modeled | Zig binds the direct C ABI and does not expose a Go-style connector layer. |
| Default busy-timeout connector tests | Not modeled | There is no Zig connector abstraction to host DSN precedence checks. |
| Higher-level `sql.DB` driver integration | Not modeled | Out of scope for the thin Zig wrapper. |
