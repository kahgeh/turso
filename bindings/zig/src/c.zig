// C FFI bindings imported directly from sdk-kit/turso.h for ABI validation.
const raw_c = @cImport({
    @cInclude("turso.h");
});

pub const turso_status_code_t = raw_c.turso_status_code_t;
pub const turso_type_t = raw_c.turso_type_t;
pub const turso_tracing_level_t = raw_c.turso_tracing_level_t;

pub const turso_database_t = raw_c.turso_database_t;
pub const turso_connection_t = raw_c.turso_connection_t;
pub const turso_statement_t = raw_c.turso_statement_t;

pub const turso_database_config_t = raw_c.turso_database_config_t;

pub const turso_database_new = raw_c.turso_database_new;
pub const turso_database_open = raw_c.turso_database_open;
pub const turso_database_connect = raw_c.turso_database_connect;
pub const turso_database_deinit = raw_c.turso_database_deinit;

pub const turso_connection_set_busy_timeout_ms = raw_c.turso_connection_set_busy_timeout_ms;
pub const turso_connection_get_autocommit = raw_c.turso_connection_get_autocommit;
pub const turso_connection_last_insert_rowid = raw_c.turso_connection_last_insert_rowid;
pub const turso_connection_prepare_single = raw_c.turso_connection_prepare_single;
pub const turso_connection_close = raw_c.turso_connection_close;
pub const turso_connection_deinit = raw_c.turso_connection_deinit;

pub const turso_statement_execute = raw_c.turso_statement_execute;
pub const turso_statement_step = raw_c.turso_statement_step;
pub const turso_statement_run_io = raw_c.turso_statement_run_io;
pub const turso_statement_reset = raw_c.turso_statement_reset;
pub const turso_statement_finalize = raw_c.turso_statement_finalize;
pub const turso_statement_n_change = raw_c.turso_statement_n_change;
pub const turso_statement_row_value_kind = raw_c.turso_statement_row_value_kind;
pub const turso_statement_row_value_bytes_count = raw_c.turso_statement_row_value_bytes_count;
pub const turso_statement_row_value_bytes_ptr = raw_c.turso_statement_row_value_bytes_ptr;
pub const turso_statement_row_value_int = raw_c.turso_statement_row_value_int;
pub const turso_statement_row_value_double = raw_c.turso_statement_row_value_double;
pub const turso_statement_bind_positional_null = raw_c.turso_statement_bind_positional_null;
pub const turso_statement_bind_positional_int = raw_c.turso_statement_bind_positional_int;
pub const turso_statement_bind_positional_double = raw_c.turso_statement_bind_positional_double;
pub const turso_statement_bind_positional_text = raw_c.turso_statement_bind_positional_text;
pub const turso_statement_bind_positional_blob = raw_c.turso_statement_bind_positional_blob;
pub const turso_statement_deinit = raw_c.turso_statement_deinit;

pub const turso_statement_column_count = raw_c.turso_statement_column_count;
pub const turso_statement_column_name = raw_c.turso_statement_column_name;
pub const turso_statement_column_decltype = raw_c.turso_statement_column_decltype;
pub const turso_statement_named_position = raw_c.turso_statement_named_position;
pub const turso_statement_parameters_count = raw_c.turso_statement_parameters_count;

pub const turso_str_deinit = raw_c.turso_str_deinit;
