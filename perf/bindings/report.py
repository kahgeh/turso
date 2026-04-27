#!/usr/bin/env python3
"""Generate an HTML chart from binding benchmark JSON lines."""

from __future__ import annotations

import argparse
import html
import json
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path, help="JSONL benchmark output")
    parser.add_argument("output", type=Path, help="HTML report path")
    return parser.parse_args()


def load_rows(path: Path) -> list[dict]:
    rows: list[dict] = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        rows.append(json.loads(line))
    if not rows:
        raise SystemExit(f"no benchmark JSON rows found in {path}")
    return rows


def workload_label(workload: str) -> str:
    return {
        "insert_txn_execute": "stmt.execute",
        "insert_txn_step": "stmt.step",
    }.get(workload, workload)


def render(rows: list[dict]) -> str:
    workloads = sorted({row["workload"] for row in rows})
    bindings = sorted({row["binding"] for row in rows})

    cards = []
    for workload in workloads:
        workload_rows = [row for row in rows if row["workload"] == workload]
        workload_max_ops = max(float(row["ops_per_sec"]) for row in workload_rows)
        bars = []
        for row in sorted(workload_rows, key=lambda item: item["binding"]):
            width = max(2.0, float(row["ops_per_sec"]) / workload_max_ops * 100.0)
            bars.append(
                f"""
                <div class="bar-row">
                  <div class="label">{html.escape(row["binding"])}</div>
                  <div class="bar-wrap">
                    <div class="bar {html.escape(row["binding"])}" style="width:{width:.2f}%"></div>
                  </div>
                  <div class="value">{float(row["ops_per_sec"]):,.0f} ops/s</div>
                </div>
                """
            )
        cards.append(
            f"""
            <section class="card">
              <h2>{html.escape(workload_label(workload))}</h2>
              {''.join(bars)}
            </section>
            """
        )

    table_rows = "\n".join(
        f"""
        <tr>
          <td>{html.escape(workload_label(row["workload"]))}</td>
          <td>{html.escape(row["binding"])}</td>
          <td>{int(row["rows"]):,}</td>
          <td>{int(row["iters"]):,}</td>
          <td>{float(row["elapsed_ms"]):,.3f}</td>
          <td>{int(row["ops"]):,}</td>
          <td>{float(row["ops_per_sec"]):,.0f}</td>
        </tr>
        """
        for row in sorted(rows, key=lambda item: (item["workload"], item["binding"]))
    )

    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Turso Binding Benchmark</title>
  <style>
    :root {{
      color-scheme: light;
      --bg: #f8fafc;
      --panel: #ffffff;
      --text: #111827;
      --muted: #64748b;
      --line: #dbe3ef;
      --rust: #2563eb;
      --zig: #f59e0b;
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      background: var(--bg);
      color: var(--text);
      font: 14px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }}
    main {{
      max-width: 1120px;
      margin: 0 auto;
      padding: 32px 20px 48px;
    }}
    header {{
      display: flex;
      justify-content: space-between;
      gap: 24px;
      align-items: end;
      margin-bottom: 24px;
    }}
    h1 {{ margin: 0; font-size: 28px; letter-spacing: 0; }}
    .meta {{ color: var(--muted); text-align: right; }}
    .grid {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
      gap: 16px;
      margin-bottom: 24px;
    }}
    .card {{
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 18px;
    }}
    h2 {{
      margin: 0 0 14px;
      font-size: 16px;
      letter-spacing: 0;
    }}
    .bar-row {{
      display: grid;
      grid-template-columns: 64px minmax(120px, 1fr) 120px;
      gap: 12px;
      align-items: center;
      margin: 10px 0;
    }}
    .label {{ font-weight: 600; }}
    .bar-wrap {{
      height: 14px;
      border-radius: 4px;
      background: #e5e7eb;
      overflow: hidden;
    }}
    .bar {{ height: 100%; border-radius: 4px; }}
    .bar.rust {{ background: var(--rust); }}
    .bar.zig {{ background: var(--zig); }}
    .value {{ color: var(--muted); text-align: right; white-space: nowrap; }}
    table {{
      width: 100%;
      border-collapse: collapse;
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      overflow: hidden;
    }}
    th, td {{
      padding: 10px 12px;
      border-bottom: 1px solid var(--line);
      text-align: right;
    }}
    th:first-child, td:first-child,
    th:nth-child(2), td:nth-child(2) {{ text-align: left; }}
    th {{ color: var(--muted); font-weight: 600; background: #f1f5f9; }}
    tr:last-child td {{ border-bottom: 0; }}
    @media (max-width: 640px) {{
      header {{ display: block; }}
      .meta {{ text-align: left; margin-top: 8px; }}
      .bar-row {{ grid-template-columns: 52px 1fr; }}
      .value {{ grid-column: 2; text-align: left; }}
      table {{ font-size: 12px; }}
      th, td {{ padding: 8px; }}
    }}
  </style>
</head>
<body>
  <main>
    <header>
      <div>
        <h1>Turso Binding Benchmark</h1>
        <div class="subtle">Throughput by workload and binding</div>
      </div>
      <div class="meta">bindings: {html.escape(", ".join(bindings))}<br>workloads: {len(workloads)}</div>
    </header>
    <div class="grid">
      {''.join(cards)}
    </div>
    <table>
      <thead>
        <tr>
          <th>workload</th>
          <th>binding</th>
          <th>rows</th>
          <th>iters</th>
          <th>elapsed ms</th>
          <th>ops</th>
          <th>ops/s</th>
        </tr>
      </thead>
      <tbody>
        {table_rows}
      </tbody>
    </table>
  </main>
</body>
</html>
"""


def main() -> None:
    args = parse_args()
    rows = load_rows(args.input)
    args.output.write_text(render(rows))
    print(args.output)


if __name__ == "__main__":
    main()
