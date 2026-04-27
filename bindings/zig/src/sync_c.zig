// Raw C FFI bindings imported directly from sync/sdk-kit/turso_sync.h.
// This module intentionally mirrors the ABI and does not manage ownership.
const raw_c = @cImport({
    @cInclude("turso_sync.h");
});

pub const turso_status_code_t = raw_c.turso_status_code_t;
pub const turso_slice_ref_t = raw_c.turso_slice_ref_t;

pub const TURSO_OK = raw_c.TURSO_OK;
pub const TURSO_DONE = raw_c.TURSO_DONE;
pub const TURSO_ROW = raw_c.TURSO_ROW;
pub const TURSO_IO = raw_c.TURSO_IO;
pub const TURSO_BUSY = raw_c.TURSO_BUSY;
pub const TURSO_INTERRUPT = raw_c.TURSO_INTERRUPT;
pub const TURSO_BUSY_SNAPSHOT = raw_c.TURSO_BUSY_SNAPSHOT;
pub const TURSO_ERROR = raw_c.TURSO_ERROR;
pub const TURSO_MISUSE = raw_c.TURSO_MISUSE;
pub const TURSO_CONSTRAINT = raw_c.TURSO_CONSTRAINT;
pub const TURSO_READONLY = raw_c.TURSO_READONLY;
pub const TURSO_DATABASE_FULL = raw_c.TURSO_DATABASE_FULL;
pub const TURSO_NOTADB = raw_c.TURSO_NOTADB;
pub const TURSO_CORRUPT = raw_c.TURSO_CORRUPT;
pub const TURSO_IOERR = raw_c.TURSO_IOERR;

pub const turso_database_config_t = raw_c.turso_database_config_t;
pub const turso_connection_t = raw_c.turso_connection_t;
pub const turso_sync_database_config_t = raw_c.turso_sync_database_config_t;
pub const turso_sync_database_t = raw_c.turso_sync_database_t;
pub const turso_sync_operation_t = raw_c.turso_sync_operation_t;
pub const turso_sync_changes_t = raw_c.turso_sync_changes_t;
pub const turso_sync_stats_t = raw_c.turso_sync_stats_t;
pub const turso_sync_io_item_t = raw_c.turso_sync_io_item_t;
pub const turso_sync_io_request_type_t = raw_c.turso_sync_io_request_type_t;
pub const turso_sync_operation_result_type_t = raw_c.turso_sync_operation_result_type_t;
pub const turso_sync_io_http_request_t = raw_c.turso_sync_io_http_request_t;
pub const turso_sync_io_http_header_t = raw_c.turso_sync_io_http_header_t;
pub const turso_sync_io_full_read_request_t = raw_c.turso_sync_io_full_read_request_t;
pub const turso_sync_io_full_write_request_t = raw_c.turso_sync_io_full_write_request_t;

pub const TURSO_SYNC_IO_NONE = raw_c.TURSO_SYNC_IO_NONE;
pub const TURSO_SYNC_IO_HTTP = raw_c.TURSO_SYNC_IO_HTTP;
pub const TURSO_SYNC_IO_FULL_READ = raw_c.TURSO_SYNC_IO_FULL_READ;
pub const TURSO_SYNC_IO_FULL_WRITE = raw_c.TURSO_SYNC_IO_FULL_WRITE;

pub const TURSO_ASYNC_RESULT_NONE = raw_c.TURSO_ASYNC_RESULT_NONE;
pub const TURSO_ASYNC_RESULT_CONNECTION = raw_c.TURSO_ASYNC_RESULT_CONNECTION;
pub const TURSO_ASYNC_RESULT_CHANGES = raw_c.TURSO_ASYNC_RESULT_CHANGES;
pub const TURSO_ASYNC_RESULT_STATS = raw_c.TURSO_ASYNC_RESULT_STATS;

pub const turso_sync_database_new = raw_c.turso_sync_database_new;
pub const turso_sync_database_open = raw_c.turso_sync_database_open;
pub const turso_sync_database_create = raw_c.turso_sync_database_create;
pub const turso_sync_database_connect = raw_c.turso_sync_database_connect;
pub const turso_sync_database_stats = raw_c.turso_sync_database_stats;
pub const turso_sync_database_checkpoint = raw_c.turso_sync_database_checkpoint;
pub const turso_sync_database_push_changes = raw_c.turso_sync_database_push_changes;
pub const turso_sync_database_wait_changes = raw_c.turso_sync_database_wait_changes;
pub const turso_sync_database_apply_changes = raw_c.turso_sync_database_apply_changes;

pub const turso_sync_operation_resume = raw_c.turso_sync_operation_resume;
pub const turso_sync_operation_result_kind = raw_c.turso_sync_operation_result_kind;
pub const turso_sync_operation_result_extract_connection = raw_c.turso_sync_operation_result_extract_connection;
pub const turso_sync_operation_result_extract_changes = raw_c.turso_sync_operation_result_extract_changes;
pub const turso_sync_operation_result_extract_stats = raw_c.turso_sync_operation_result_extract_stats;

pub const turso_sync_database_io_take_item = raw_c.turso_sync_database_io_take_item;
pub const turso_sync_database_io_step_callbacks = raw_c.turso_sync_database_io_step_callbacks;
pub const turso_sync_database_io_request_kind = raw_c.turso_sync_database_io_request_kind;
pub const turso_sync_database_io_request_http = raw_c.turso_sync_database_io_request_http;
pub const turso_sync_database_io_request_http_header = raw_c.turso_sync_database_io_request_http_header;
pub const turso_sync_database_io_request_full_read = raw_c.turso_sync_database_io_request_full_read;
pub const turso_sync_database_io_request_full_write = raw_c.turso_sync_database_io_request_full_write;
pub const turso_sync_database_io_poison = raw_c.turso_sync_database_io_poison;
pub const turso_sync_database_io_status = raw_c.turso_sync_database_io_status;
pub const turso_sync_database_io_push_buffer = raw_c.turso_sync_database_io_push_buffer;
pub const turso_sync_database_io_done = raw_c.turso_sync_database_io_done;

pub const turso_sync_database_deinit = raw_c.turso_sync_database_deinit;
pub const turso_sync_operation_deinit = raw_c.turso_sync_operation_deinit;
pub const turso_sync_database_io_item_deinit = raw_c.turso_sync_database_io_item_deinit;
pub const turso_sync_changes_deinit = raw_c.turso_sync_changes_deinit;
