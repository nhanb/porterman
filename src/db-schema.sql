-- Must keep certain text CHECK constraints in sync with enums.zig

create table state (
    id integer primary key check(id=0),
    method text
        check(method in ('GET', 'HEAD', 'POST', 'PUT', 'DELETE', 'OPTIONS', 'TRACE', 'PATCH'))
        default 'GET',
    url text default 'https://vnexpress.net/',
    sending integer check (sending in (0, 1)) default 0,
    response_status integer check (0 <= response_status < 1024) null,
    response_body text default null,
    app_status text default 'Ready'
);
insert into state(id) values(0);

create table task (
    id integer primary key,
    name text check(name in ('send_request')),
    blocking integer check(blocking in (0, 1)) default 0,
    data blob -- jsonb
);
