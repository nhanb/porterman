//! Must keep these enum values in sync with CHECK constraints in db-schema.sql
pub const HttpMethod = enum {
    GET,
    HEAD,
    POST,
    PUT,
    DELETE,
    OPTIONS,
    TRACE,
    PATCH,
};

pub const Task = enum {
    send_request,
};
