const std = @import("std");
const Allocator = std.mem.Allocator;
const dvui = @import("dvui");
const enums = @import("enums.zig");
const Database = @import("Database.zig");
const curl = @import("curl.zig");

pub fn sendRequest(
    gpa: std.mem.Allocator,
    win: *dvui.Window,
    task_id: i64,
) !void {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    const arena = arena_state.allocator();
    defer arena_state.deinit();

    const db = try Database.init();

    const row = (try db.selectRow(
        \\select
        \\  data ->> '$.method',
        \\  data ->> '$.url'
        \\from task where id=?
    ,
        .{task_id},
    )).?;
    defer row.deinit();

    const http_method = std.meta.stringToEnum(std.http.Method, row.text(0)).?;
    const url = row.text(1);

    _ = http_method;
    const resp = try curl.get(arena, url);

    try db.begin();
    errdefer db.rollback();

    try db.exec(
        "update state set response_status=?, response_body=?, response_body_changed=1",
        .{ @intFromEnum(resp.status), resp.body },
    );

    try db.execNoArgs("delete from response_headers");
    for (resp.headers) |h| {
        try db.exec(
            "insert into response_headers (name, value) values (?, ?)",
            .{ h[0], h[1] },
        );
        std.log.info("Header: {s}: {s}", .{ h[0], h[1] });
    }

    try db.exec("delete from task where id=?", .{task_id});
    try db.execNoArgs("update state set app_status='Finished request'");
    try db.commit();

    dvui.refresh(win, @src(), null);
}
