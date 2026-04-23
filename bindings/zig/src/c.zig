// Minimal C type definitions from sdk-kit/turso.h
// Full FFI bindings are added incrementally as wrappers are built.

pub const c_int = std.c_int;
pub const c_char = std.c_char;
pub const c_uint = std.c_uint;
pub const c_size_t = usize;
pub const c_longlong = i64;
pub const c_double = f64;
pub const c_bool = bool;

pub const turso_status_code_t = enum(c_int) {
    TURSO_OK = 0,
    TURSO_DONE = 1,
    TURSO_ROW = 2,
    TURSO_IO = 3,
    TURSO_BUSY = 4,
    TURSO_INTERRUPT = 5,
    TURSO_BUSY_SNAPSHOT = 6,
    TURSO_ERROR = 127,
    TURSO_MISUSE = 128,
    TURSO_CONSTRAINT = 129,
    TURSO_READONLY = 130,
    TURSO_DATABASE_FULL = 131,
    TURSO_NOTADB = 132,
    TURSO_CORRUPT = 133,
    TURSO_IOERR = 134,
};

pub const turso_type_t = enum(c_int) {
    TURSO_TYPE_UNKNOWN = 0,
    TURSO_TYPE_INTEGER = 1,
    TURSO_TYPE_REAL = 2,
    TURSO_TYPE_TEXT = 3,
    TURSO_TYPE_BLOB = 4,
    TURSO_TYPE_NULL = 5,
};

pub const turso_tracing_level_t = enum(c_int) {
    TURSO_TRACING_LEVEL_ERROR = 1,
    TURSO_TRACING_LEVEL_WARN = 2,
    TURSO_TRACING_LEVEL_INFO = 3,
    TURSO_TRACING_LEVEL_DEBUG = 4,
    TURSO_TRACING_LEVEL_TRACE = 5,
};

// Opaque pointer types for handle-oriented C API.
pub const turso_database_t = extern struct {};
pub const turso_connection_t = extern struct {};
pub const turso_statement_t = extern struct {};

const std = @import("std");
