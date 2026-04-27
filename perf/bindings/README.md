# Binding Benchmarks

Small cross-binding benchmark drivers for measuring binding overhead with the
same local database workloads.

Run all implemented bindings:

```bash
./perf/bindings/run.sh
```

Run one workload:

```bash
./perf/bindings/run.sh --workload point_select --rows 10000 --iters 5
```

Implemented bindings:

- `rust`
- `zig`

Implemented workloads:

- `open_database`: build an in-memory database repeatedly.
- `open_close`: build an in-memory database and connection repeatedly.
- `prepare_step`: prepare `SELECT 1` and step it to completion.
- `insert_txn`: insert `rows` rows inside one transaction.
- `point_select`: load `rows` indexed rows, then perform `rows` indexed lookups.
- `scan_borrowed`: load `rows` rows, then scan ids through the thinnest available value path.
- `scan_owned`: load `rows` rows, then scan and materialize owned row values.
- `query_collect`: load `rows` rows, then use high-level query APIs and collect owned rows.

Each driver prints one JSON object per run:

```json
{"binding":"rust","workload":"scan","rows":10000,"iters":5,"elapsed_ms":12.345,"ops":50000,"ops_per_sec":4050221.23}
```

By default the runner uses Cargo `bench-profile` and Zig `ReleaseFast`.
The Zig driver links the native static archives from `target/<profile>`, so the
runner builds `turso_sdk_kit` and `turso_sync_sdk_kit` first.
