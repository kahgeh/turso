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
pub const turso_database_deinit = raw_c.turso_database_deinit;

pub const turso_str_deinit = raw_c.turso_str_deinit;
