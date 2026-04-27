# Turso Zig Binding

Zig bindings for [TursoDB](https://turso.tech) local database access and the sync C ABI. This package wraps the `turso_sdk_kit` and `turso_sync_sdk_kit` C APIs and exposes thin Zig modules plus higher-level convenience helpers.

## Layout

```text
bindings/zig/
├── build.zig
├── README.md
├── src/
│   ├── root.zig
│   ├── c.zig
│   ├── sync.zig
│   ├── sync_c.zig
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
    ├── sync_config.zig
    ├── types.zig
```

## Supported Environment

The binding is validated in this repository on macOS with the local development target. The build links the Rust static archive directly and also links `CoreFoundation`, so other targets may need additional build work before they are supported.

## Native Library

The Zig package consumes the `turso_sdk_kit` and `turso_sync_sdk_kit` static libraries produced by the Rust workspace.

Build the native libraries first:

```bash
cargo build --package turso_sdk_kit --lib
cargo build --package turso_sync_sdk_kit --lib
```

The current `build.zig` expects the archives at:

```text
../../target/debug/libturso_sdk_kit.a
../../target/debug/libturso_sync_sdk_kit.a
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

    var conn = try db.connect();
    defer conn.deinit();

    var create_stmt = try conn.prepareSingle("CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT)");
    defer {
        create_stmt.finalize() catch {};
        create_stmt.deinit();
    }
    _ = try create_stmt.execute(.{});

    var insert_stmt = try conn.prepareSingle("INSERT INTO t(name) VALUES (?1)");
    defer {
        insert_stmt.finalize() catch {};
        insert_stmt.deinit();
    }
    _ = try insert_stmt.execute(.{"ada"});

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

## API Layers

- Zig-native layer: use `turso.Builder`, `turso.Database`, `turso.Connection`, `turso.Statement`, `Connection.rows()`, and owned-copy helpers for normal application code.
- Raw C ABI layer: use `turso.raw` only when integrating with C-level handles or validating ABI behavior. It mirrors `sdk-kit/turso.h` and does not add Zig ownership policy.
- Sync Zig-native layer: use `turso.sync.Builder`, `turso.sync.Database`, and sync operation helpers for synced database handles.
- Raw sync C ABI layer: use `turso.raw_sync` only when integrating directly with `sync/sdk-kit/turso_sync.h`.

## Ownership Rules

- `Database`, `Connection`, and `Statement` handles must be explicitly deinitialized.
- `connect()`, `prepareSingle()`, and `prepareFirst()` return value handles.
- `Connection.close()` and `Statement.finalize()` are separate from `deinit()`.
- Text and blob row values returned by the wrapper are owned copies in Zig memory.
- `Connection.query()` returns owned copied rows and metadata; call `QueryResult.deinit()` to release them.
- `Connection.rows()` streams row views; borrowed text/blob slices are valid until the next step, reset, finalize, or `Rows.deinit()`.
- Pass `err.Diagnostic` to diagnostic variants such as `executeWithDiagnostic()` to keep engine error messages.
- `Statement.execute(.{})` runs with existing bindings; `Statement.execute(.{ value1, value2 })` resets and binds positional parameters before execution.
- `Statement.execute(...)` and `step()` auto-drive `TURSO_IO`; `executeOnce()` and `stepOnce()` expose it to caller-managed event loops.
- Metadata strings returned by `columnName()` and `columnDecltype()` are owned copies in Zig memory.
- `Statement.namedPosition()` returns `!?usize`; null means the named parameter is absent.
- Strings allocated by Turso are released inside the wrapper with `turso_str_deinit()`.
- `prepareFirst()` can return a null statement when the remaining SQL contains only whitespace or comments.

## Known Performance Notes

`prepareSingle()` uses the existing C ABI, `turso_connection_prepare_single`.
The Rust SDK also has a direct `rsapi` path and `prepare_cached()` support, but
the C ABI does not expose the SDK statement cache. As a result, benchmark
workloads that repeatedly prepare the same SQL, such as `perf/bindings`
`prepare_step`, include C boundary and statement-wrapper overhead for Zig that
Rust `rsapi` does not pay. See
[tursodatabase/turso#4548](https://github.com/tursodatabase/turso/issues/4548)
for the related prepared-statement caching issue.

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
- engine diagnostic message capture
- synchronous and caller-driven async IO stepping
- file-backed reopen and duplicate-connection coverage
- encryption reopen and wrong-key coverage
- busy-timeout and concurrent-writer contention coverage
- MVCC `BEGIN CONCURRENT` writer coverage
- async `TURSO_IO` retry coverage
- builder, execute/query, execute-batch, and transaction convenience coverage
- sync ABI import, sync builder defaults, partial sync config construction, and remote encryption reserved-byte mapping
- sync end-to-end coverage for bootstrap, persisted bootstrap/config, pull, push, checkpoint, and partial prefix bootstrap

## Sync Layer

The Zig binding now imports `sync/sdk-kit/turso_sync.h` as `turso.raw_sync` and exposes an initial native wrapper under `turso.sync`.

```zig
const std = @import("std");
const turso = @import("turso");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var db = try turso.sync.Builder.newRemote(allocator, "local.db")
        .withRemoteUrl("https://db.turso.io")
        .withClientName("example-zig-client")
        .build();
    defer db.deinit();

    var conn = try db.connect();
    defer conn.deinit();

    _ = try conn.execute("INSERT INTO notes(content) VALUES ('hello')");
    try db.push();
    _ = try db.pull();

    var stats = try db.stats();
    defer stats.deinit();
}
```

Sync operations are driven synchronously by the Zig wrapper. File IO requests are handled directly by the binding. HTTP requests use a default `std.http.Client` executor, and callers can override it with `turso.sync.IoExecutor` when they need custom TLS, proxy, platform networking, or event-loop integration.

`turso.sync.Changes` owns `turso_sync_changes_t` unless consumed by `Database.applyChanges()`. `turso.sync.Stats.revision` is copied into Zig-owned memory before the underlying operation is deinitialized.

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
| Higher-level execute/query helpers | Supported | `Connection.execute(sql)`, `Statement.execute(.{ ... })`, `executeBatch()`, and `query()` preserve owned-copy row semantics. |
| Transaction ergonomics | Supported | `Connection.transaction()` with explicit `commit()` / `rollback()`. |
| Rust sync layer | Supported | Zig binds `sync/sdk-kit/turso_sync.h`, links `turso_sync_sdk_kit`, exposes config/lifecycle wrappers, drives sync IO, and provides default HTTP execution with a custom executor escape hatch. |
| DSN parsing and connector options | Not modeled | Zig binds the direct C ABI and does not expose a Go-style connector layer. |
| Default busy-timeout connector tests | Not modeled | There is no Zig connector abstraction to host DSN precedence checks. |
| Higher-level `sql.DB` driver integration | Not modeled | Out of scope for the thin Zig wrapper. |
