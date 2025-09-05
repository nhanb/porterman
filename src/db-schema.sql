create table state (
    id integer primary key check(id=0),
    method text
        check(method in ('GET', 'HEAD', 'POST', 'PUT', 'DELETE', 'OPTIONS', 'TRACE', 'PATCH'))
        default 'GET',
    url text default 'https://httpbin.org/headers',
    sending integer check (sending in (0, 1)) default 0,
    response_status integer default -1,
    response_body text default ''
);
insert into state(id) values(0);
