#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROFILE="bench-profile"
OPTIMIZE="ReleaseFast"
BINDINGS="rust,zig"
WORKLOAD="point_select"
ROWS="10000"
ITERS="5"

usage() {
  cat >&2 <<'EOF'
usage: ./perf/bindings/run.sh [options]

options:
  --bindings rust,zig       comma-separated binding list
  --workload NAME           open_database, open_close, prepare_step,
                            insert_txn_execute, insert_txn_step,
                            point_select, scan_borrowed, scan_owned, or query_collect
  --rows N                  rows per iteration
  --iters N                 iteration count
  --profile NAME            Cargo profile and target/<profile> native archive dir
  --zig-optimize MODE       Zig optimize mode
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bindings) BINDINGS="$2"; shift 2 ;;
    --workload) WORKLOAD="$2"; shift 2 ;;
    --rows) ROWS="$2"; shift 2 ;;
    --iters) ITERS="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    --zig-optimize) OPTIMIZE="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

IFS=',' read -r -a BINDING_LIST <<< "$BINDINGS"

cargo build \
  --package turso_sdk_kit \
  --package turso_sync_sdk_kit \
  --package binding-bench-rust \
  --profile "$PROFILE" >/dev/null

for binding in "${BINDING_LIST[@]}"; do
  case "$binding" in
    rust)
      "$ROOT/target/$PROFILE/binding-bench-rust" \
        --workload "$WORKLOAD" \
        --rows "$ROWS" \
        --iters "$ITERS"
      ;;
    zig)
      zig build \
        --build-file "$ROOT/perf/bindings/zig/build.zig" \
        -Dnative-lib-dir="../../../target/$PROFILE" \
        -Doptimize="$OPTIMIZE" \
        run -- \
        --workload "$WORKLOAD" \
        --rows "$ROWS" \
        --iters "$ITERS"
      ;;
    *)
      echo "unsupported binding: $binding" >&2
      exit 2
      ;;
  esac
done
