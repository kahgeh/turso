use std::env;
use std::time::Instant;

use turso::{Builder, Value};

#[derive(Clone, Copy)]
enum Workload {
    OpenClose,
    InsertTxn,
    PointSelect,
    Scan,
}

impl Workload {
    fn parse(value: &str) -> Result<Self, String> {
        match value {
            "open_close" => Ok(Self::OpenClose),
            "insert_txn" => Ok(Self::InsertTxn),
            "point_select" => Ok(Self::PointSelect),
            "scan" => Ok(Self::Scan),
            _ => Err(format!("unknown workload: {value}")),
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::OpenClose => "open_close",
            Self::InsertTxn => "insert_txn",
            Self::PointSelect => "point_select",
            Self::Scan => "scan",
        }
    }
}

struct Args {
    workload: Workload,
    rows: usize,
    iters: usize,
}

impl Args {
    fn parse() -> Result<Self, String> {
        let mut workload = Workload::PointSelect;
        let mut rows = 10_000;
        let mut iters = 5;

        let mut args = env::args().skip(1);
        while let Some(arg) = args.next() {
            match arg.as_str() {
                "--workload" => {
                    let value = args
                        .next()
                        .ok_or_else(|| "--workload requires a value".to_string())?;
                    workload = Workload::parse(&value)?;
                }
                "--rows" => {
                    let value = args
                        .next()
                        .ok_or_else(|| "--rows requires a value".to_string())?;
                    rows = value
                        .parse()
                        .map_err(|_| format!("invalid --rows value: {value}"))?;
                }
                "--iters" => {
                    let value = args
                        .next()
                        .ok_or_else(|| "--iters requires a value".to_string())?;
                    iters = value
                        .parse()
                        .map_err(|_| format!("invalid --iters value: {value}"))?;
                }
                "--help" | "-h" => {
                    print_help();
                    std::process::exit(0);
                }
                _ => return Err(format!("unknown argument: {arg}")),
            }
        }

        Ok(Self {
            workload,
            rows,
            iters,
        })
    }
}

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let args = Args::parse().unwrap_or_else(|err| {
        eprintln!("{err}");
        print_help();
        std::process::exit(2);
    });

    let result = match args.workload {
        Workload::OpenClose => open_close(args.rows, args.iters).await,
        Workload::InsertTxn => insert_txn(args.rows, args.iters).await,
        Workload::PointSelect => point_select(args.rows, args.iters).await,
        Workload::Scan => scan(args.rows, args.iters).await,
    };

    let (elapsed_ms, ops) = result.unwrap_or_else(|err| {
        eprintln!("{err}");
        std::process::exit(1);
    });
    print_result(
        "rust",
        args.workload,
        args.rows,
        args.iters,
        elapsed_ms,
        ops,
    );
}

fn print_help() {
    eprintln!(
        "usage: binding-bench-rust [--workload open_close|insert_txn|point_select|scan] [--rows N] [--iters N]"
    );
}

fn print_result(
    binding: &str,
    workload: Workload,
    rows: usize,
    iters: usize,
    elapsed_ms: f64,
    ops: usize,
) {
    let ops_per_sec = if elapsed_ms > 0.0 {
        ops as f64 / (elapsed_ms / 1000.0)
    } else {
        0.0
    };
    println!(
        "{{\"binding\":\"{}\",\"workload\":\"{}\",\"rows\":{},\"iters\":{},\"elapsed_ms\":{:.3},\"ops\":{},\"ops_per_sec\":{:.3}}}",
        binding,
        workload.as_str(),
        rows,
        iters,
        elapsed_ms,
        ops,
        ops_per_sec
    );
}

async fn open_close(rows: usize, iters: usize) -> turso::Result<(f64, usize)> {
    let reps = rows.saturating_mul(iters).max(1);
    let started = Instant::now();
    for _ in 0..reps {
        let db = Builder::new_local(":memory:").build().await?;
        let conn = db.connect()?;
        drop(conn);
        drop(db);
    }
    Ok((started.elapsed().as_secs_f64() * 1000.0, reps))
}

async fn insert_txn(rows: usize, iters: usize) -> turso::Result<(f64, usize)> {
    let db = Builder::new_local(":memory:").build().await?;
    let conn = db.connect()?;
    conn.execute("CREATE TABLE t(id INTEGER PRIMARY KEY, value TEXT)", ())
        .await?;

    let started = Instant::now();
    let mut inserted = 0;
    for iter in 0..iters {
        conn.execute("BEGIN", ()).await?;
        let mut stmt = conn
            .prepare("INSERT INTO t(id, value) VALUES (?1, ?2)")
            .await?;
        for row in 0..rows {
            let id = (iter * rows + row) as i64;
            stmt.execute((id, "payload")).await?;
            inserted += 1;
        }
        conn.execute("COMMIT", ()).await?;
    }
    Ok((started.elapsed().as_secs_f64() * 1000.0, inserted))
}

async fn point_select(rows: usize, iters: usize) -> turso::Result<(f64, usize)> {
    let db = Builder::new_local(":memory:").build().await?;
    let conn = db.connect()?;
    load_rows(&conn, rows).await?;

    let started = Instant::now();
    let mut found = 0;
    for _ in 0..iters {
        let mut stmt = conn.prepare("SELECT value FROM t WHERE id = ?1").await?;
        for row in 0..rows {
            let result = stmt.query_row((row as i64,)).await?;
            if let Value::Text(value) = result.get_value(0)? {
                std::hint::black_box(value);
                found += 1;
            }
        }
    }
    Ok((started.elapsed().as_secs_f64() * 1000.0, found))
}

async fn scan(rows: usize, iters: usize) -> turso::Result<(f64, usize)> {
    let db = Builder::new_local(":memory:").build().await?;
    let conn = db.connect()?;
    load_rows(&conn, rows).await?;

    let started = Instant::now();
    let mut scanned = 0;
    let mut checksum = 0i64;
    for _ in 0..iters {
        let mut rows_iter = conn.query("SELECT id FROM t", ()).await?;
        while let Some(row) = rows_iter.next().await? {
            if let Value::Integer(value) = row.get_value(0)? {
                checksum = checksum.wrapping_add(value);
                scanned += 1;
            }
        }
    }
    std::hint::black_box(checksum);
    Ok((started.elapsed().as_secs_f64() * 1000.0, scanned))
}

async fn load_rows(conn: &turso::Connection, rows: usize) -> turso::Result<()> {
    conn.execute("CREATE TABLE t(id INTEGER PRIMARY KEY, value TEXT)", ())
        .await?;
    conn.execute("BEGIN", ()).await?;
    let mut stmt = conn
        .prepare("INSERT INTO t(id, value) VALUES (?1, ?2)")
        .await?;
    for row in 0..rows {
        stmt.execute((row as i64, "payload")).await?;
    }
    conn.execute("COMMIT", ()).await?;
    Ok(())
}
