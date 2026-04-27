use std::env;
use std::sync::Arc;
use std::time::Instant;

use turso::{Builder, Value};
use turso_sdk_kit::rsapi::{
    TursoConnection, TursoDatabase, TursoDatabaseConfig, TursoError, TursoStatusCode,
    Value as SdkValue,
};

type BenchResult = anyhow::Result<(f64, usize)>;

#[derive(Clone, Copy)]
enum Workload {
    OpenDatabase,
    OpenClose,
    PrepareStep,
    InsertTxn,
    PointSelect,
    ScanBorrowed,
    ScanOwned,
    QueryCollect,
}

impl Workload {
    fn parse(value: &str) -> Result<Self, String> {
        match value {
            "open_database" => Ok(Self::OpenDatabase),
            "open_close" => Ok(Self::OpenClose),
            "prepare_step" => Ok(Self::PrepareStep),
            "insert_txn" => Ok(Self::InsertTxn),
            "point_select" => Ok(Self::PointSelect),
            "scan_borrowed" => Ok(Self::ScanBorrowed),
            "scan_owned" => Ok(Self::ScanOwned),
            "query_collect" => Ok(Self::QueryCollect),
            _ => Err(format!("unknown workload: {value}")),
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::OpenDatabase => "open_database",
            Self::OpenClose => "open_close",
            Self::PrepareStep => "prepare_step",
            Self::InsertTxn => "insert_txn",
            Self::PointSelect => "point_select",
            Self::ScanBorrowed => "scan_borrowed",
            Self::ScanOwned => "scan_owned",
            Self::QueryCollect => "query_collect",
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
        Workload::OpenDatabase => open_database(args.rows, args.iters).await,
        Workload::OpenClose => open_close(args.rows, args.iters).await,
        Workload::PrepareStep => prepare_step(args.rows, args.iters),
        Workload::InsertTxn => insert_txn(args.rows, args.iters).await,
        Workload::PointSelect => point_select(args.rows, args.iters).await,
        Workload::ScanBorrowed => scan_borrowed(args.rows, args.iters),
        Workload::ScanOwned => scan_owned(args.rows, args.iters),
        Workload::QueryCollect => query_collect(args.rows, args.iters).await,
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
        "usage: binding-bench-rust [--workload open_database|open_close|prepare_step|insert_txn|point_select|scan_borrowed|scan_owned|query_collect] [--rows N] [--iters N]"
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

async fn open_close(rows: usize, iters: usize) -> BenchResult {
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

async fn open_database(rows: usize, iters: usize) -> BenchResult {
    let reps = rows.saturating_mul(iters).max(1);
    let started = Instant::now();
    for _ in 0..reps {
        let db = Builder::new_local(":memory:").build().await?;
        drop(db);
    }
    Ok((started.elapsed().as_secs_f64() * 1000.0, reps))
}

fn prepare_step(rows: usize, iters: usize) -> BenchResult {
    let reps = rows.saturating_mul(iters).max(1);
    let (_db, conn) = sdk_open_connect()?;
    let started = Instant::now();
    for _ in 0..reps {
        let mut stmt = sdk(conn.prepare_single("SELECT 1"))?;
        if sdk(stmt.step(None))? != TursoStatusCode::Row {
            anyhow::bail!("expected row");
        }
        if sdk(stmt.step(None))? != TursoStatusCode::Done {
            anyhow::bail!("expected done");
        }
    }
    Ok((started.elapsed().as_secs_f64() * 1000.0, reps))
}

async fn insert_txn(rows: usize, iters: usize) -> BenchResult {
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

async fn point_select(rows: usize, iters: usize) -> BenchResult {
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

async fn query_collect(rows: usize, iters: usize) -> BenchResult {
    let db = Builder::new_local(":memory:").build().await?;
    let conn = db.connect()?;
    load_rows(&conn, rows).await?;

    let started = Instant::now();
    let mut scanned = 0;
    let mut checksum = 0i64;
    for _ in 0..iters {
        let mut rows_iter = conn.query("SELECT id, value FROM t", ()).await?;
        let mut collected = Vec::with_capacity(rows);
        while let Some(row) = rows_iter.next().await? {
            if let Value::Integer(value) = row.get_value(0)? {
                checksum = checksum.wrapping_add(value);
                scanned += 1;
            }
            collected.push(row.get_value(1)?);
        }
        std::hint::black_box(collected);
    }
    std::hint::black_box(checksum);
    Ok((started.elapsed().as_secs_f64() * 1000.0, scanned))
}

fn scan_borrowed(rows: usize, iters: usize) -> BenchResult {
    let (_db, conn) = sdk_open_connect()?;
    sdk_load_rows(&conn, rows)?;

    let started = Instant::now();
    let mut scanned = 0;
    let mut checksum = 0i64;
    for _ in 0..iters {
        let mut stmt = sdk(conn.prepare_single("SELECT id FROM t"))?;
        loop {
            match sdk(stmt.step(None))? {
                TursoStatusCode::Row => {
                    if let SdkValue::Numeric(turso::core::Numeric::Integer(value)) =
                        sdk(stmt.row_value(0))?
                    {
                        checksum = checksum.wrapping_add(value);
                        scanned += 1;
                    }
                }
                TursoStatusCode::Done => break,
                TursoStatusCode::Io => sdk(stmt.run_io())?,
            }
        }
    }
    std::hint::black_box(checksum);
    Ok((started.elapsed().as_secs_f64() * 1000.0, scanned))
}

fn scan_owned(rows: usize, iters: usize) -> BenchResult {
    let (_db, conn) = sdk_open_connect()?;
    sdk_load_rows(&conn, rows)?;

    let started = Instant::now();
    let mut scanned = 0;
    let mut checksum = 0i64;
    for _ in 0..iters {
        let mut stmt = sdk(conn.prepare_single("SELECT id, value FROM t"))?;
        loop {
            match sdk(stmt.step(None))? {
                TursoStatusCode::Row => {
                    let id = sdk(stmt.row_value(0))?;
                    let value = sdk(stmt.row_value(1))?;
                    if let SdkValue::Numeric(turso::core::Numeric::Integer(value)) = id {
                        checksum = checksum.wrapping_add(value);
                        scanned += 1;
                    }
                    std::hint::black_box(value);
                }
                TursoStatusCode::Done => break,
                TursoStatusCode::Io => sdk(stmt.run_io())?,
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

fn sdk_open_connect() -> anyhow::Result<(Arc<TursoDatabase>, Arc<TursoConnection>)> {
    let db = TursoDatabase::new(TursoDatabaseConfig {
        path: ":memory:".to_string(),
        experimental_features: None,
        async_io: false,
        encryption: None,
        vfs: None,
        io: None,
        db_file: None,
    });
    match sdk(db.open())? {
        turso::core::types::IOResult::Done(()) => {}
        turso::core::types::IOResult::IO(_) => anyhow::bail!("unexpected IO from sync open"),
    }
    let conn = sdk(db.connect())?;
    Ok((db, conn))
}

fn sdk_exec(conn: &Arc<TursoConnection>, sql: &str) -> anyhow::Result<()> {
    let mut stmt = sdk(conn.prepare_single(sql))?;
    loop {
        match sdk(stmt.step(None))? {
            TursoStatusCode::Row => {}
            TursoStatusCode::Done => return Ok(()),
            TursoStatusCode::Io => sdk(stmt.run_io())?,
        }
    }
}

fn sdk_load_rows(conn: &Arc<TursoConnection>, rows: usize) -> anyhow::Result<()> {
    sdk_exec(conn, "CREATE TABLE t(id INTEGER PRIMARY KEY, value TEXT)")?;
    sdk_exec(conn, "BEGIN")?;
    let mut stmt = sdk(conn.prepare_single("INSERT INTO t(id, value) VALUES (?1, ?2)"))?;
    for row in 0..rows {
        sdk(stmt.reset())?;
        sdk(stmt.bind_positional(1, SdkValue::from_i64(row as i64)))?;
        sdk(stmt.bind_positional(2, SdkValue::build_text("payload")))?;
        loop {
            match sdk(stmt.step(None))? {
                TursoStatusCode::Row => {}
                TursoStatusCode::Done => break,
                TursoStatusCode::Io => sdk(stmt.run_io())?,
            }
        }
    }
    sdk_exec(conn, "COMMIT")?;
    Ok(())
}

fn sdk<T>(result: Result<T, TursoError>) -> anyhow::Result<T> {
    result.map_err(|err| anyhow::anyhow!("{err}"))
}
