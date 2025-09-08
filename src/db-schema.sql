-- Must keep certain text CHECK constraints in sync with enums.zig
create table state (
    id integer primary key check(id=0),
    method text
        check(method in ('GET', 'HEAD', 'POST', 'PUT', 'DELETE', 'OPTIONS', 'TRACE', 'PATCH'))
        default 'GET',
    url text default 'https://httpbin.org/headers',
    sending integer check (sending in (0, 1)) default 0,
    response_status integer check (0 <= response_status < 1024) default 0,
    response_body text default '',
    blocking_task text check(blocking_task in ('send_request')) default null
);
insert into state(id) values(0);
