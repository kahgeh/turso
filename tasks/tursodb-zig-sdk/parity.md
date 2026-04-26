# Zig Binding Parity Plan

This file tracks the remaining work needed if the Zig binding is expected to follow the Rust-style higher-level wrapper shape, rather than stopping at the thin ABI layer.

The current Zig binding already covers the low-level C ABI contract and the tested local database surface. The gaps below are specifically about the higher-level Rust-like ergonomics:

- builder-style database construction
- async-aware open/connect flow
- convenience `execute` / `query` wrappers
- transaction ergonomics
- optional sync-layer parity, if desired

## Completed Subtasks

### Subtask A: add a builder-style database wrapper

Commit goal:

- introduce a Zig builder that mirrors the Rust `Builder::new_local(...)` shape
- keep the direct `Database` / `Connection` handle API available underneath
- expose explicit configuration for path, encryption, async IO, and VFS

Files:

- `bindings/zig/src/database.zig`
- `bindings/zig/src/root.zig`
- `bindings/zig/tests/`

Verification:

- `cargo build --package turso_sdk_kit --lib`
- `zig build test --summary all`

Suggested commit title:

- `bindings/zig: add builder-style database wrapper`

Status: complete. `turso.db.Builder` / root `turso.Builder` now supports `newLocal`, explicit async IO, VFS, experimental features, encryption, `build()`, and build-plus-connect ownership.

### Subtask B: add async open/connect convenience helpers

Commit goal:

- mirror Rust’s higher-level `build().await` / `connect()` lifecycle in Zig-idiomatic form
- keep async IO explicit and testable
- ensure callers can open and connect without manually handling low-level status plumbing

Files:

- `bindings/zig/src/database.zig`
- `bindings/zig/src/connection.zig`
- `bindings/zig/src/statement.zig`

Verification:

- `cargo build --package turso_sdk_kit --lib`
- `zig build test --summary all`

Suggested commit title:

- `bindings/zig: add async open and connect helpers`

Status: complete within the current C ABI boundary. The builder exposes async IO configuration, `Database.open()` aliases the explicit open lifecycle, and statement execution/query helpers continue to drive statement-level `TURSO_IO` transparently. The C ABI does not expose a database-open `run_io` hook, so fully caller-driven async database open cannot be implemented in Zig without extending `turso_sdk_kit`.

### Subtask C: add higher-level execute/query helpers

Commit goal:

- add convenience wrappers for direct `execute`, `query`, and `execute_batch` flows
- keep the existing explicit statement API available
- preserve owned-copy semantics for rows and metadata

Files:

- `bindings/zig/src/connection.zig`
- `bindings/zig/src/statement.zig`
- `bindings/zig/tests/`

Verification:

- `cargo build --package turso_sdk_kit --lib`
- `zig build test --summary all`

Suggested commit title:

- `bindings/zig: add convenience execute and query helpers`

Status: complete. `Connection.execute`, `executeBatch`, and `query` are available, while the explicit statement API remains unchanged. Query rows and metadata are owned Zig copies.

### Subtask D: add transaction ergonomics

Commit goal:

- add a transaction wrapper that matches the higher-level Rust style
- keep commit and rollback behavior explicit
- preserve the current low-level connection and statement handles underneath

Files:

- `bindings/zig/src/connection.zig`
- `bindings/zig/src/statement.zig`
- `bindings/zig/tests/`

Verification:

- `cargo build --package turso_sdk_kit --lib`
- `zig build test --summary all`

Suggested commit title:

- `bindings/zig: add transaction wrapper ergonomics`

Status: complete. `Connection.transaction()` returns a transaction wrapper with explicit `commit()` and `rollback()`.

### Subtask E: decide whether Zig should expose a sync layer

Commit goal:

- document whether Zig should gain Rust-style sync support
- if yes, add a separate sync wrapper and tests
- if no, document that the Zig binding remains local-only by design

Files:

- `bindings/zig/README.md`
- `tasks/tursodb-zig-sdk/parity.md`
- optionally `bindings/zig/src/`

Verification:

- `cargo build --package turso_sdk_kit --lib`
- `zig build test --summary all`

Suggested commit title:

- `bindings/zig: document sync-layer parity decision`

Status: complete. Zig remains local-only by design until the C ABI exposes sync primitives; this is documented in `bindings/zig/README.md`.
