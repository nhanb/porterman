const std = @import("std");
const mem = std.mem;
const dvui = @import("dvui");

const curl = @import("curl.zig");
const enums = @import("enums.zig");
const State = @import("State.zig");
const Database = @import("Database.zig");
const tasks = @import("tasks.zig");

pub const Action = union(enum) {
    change_method: enums.HttpMethod,
    change_url: []const u8,

    start_request: struct {
        url: []const u8,
        method: enums.HttpMethod,
    },
    finish_request: struct {
        task_id: i64,
        curl_response: curl.Response,
    },

    change_response_tab: State.ResponseTab,
};

pub fn exec(
    gpa: mem.Allocator,
    arena: mem.Allocator,
    win: *dvui.Window,
    db: Database,
    action: Action,
) !void {
    try db.begin();
    errdefer db.rollback();

    switch (action) {
        .change_method => |method| {
            try db.exec("update state set method=?;", .{@tagName(method)});
        },
        .change_url => |url| {
            try db.exec("update state set url=?;", .{url});
        },
        .start_request => |req| {
            try db.execNoArgs(
                "update state set app_status='Sending request...';",
            );

            const task_id = try db.selectInt(
                \\insert into task (blocking, name, data) values (
                \\  1,
                \\  ?,
                \\  jsonb_object(
                \\    'method', ?,
                \\    'url', ?
                \\  )
                \\) returning id;
            , .{
                @tagName(enums.Task.send_request),
                @tagName(req.method),
                req.url,
            });

            _ = try std.Thread.spawn(
                .{},
                tasks.sendRequest,
                .{ gpa, win, task_id },
            );
        },
        .finish_request => |data| {
            const resp = data.curl_response;
            const task_id = data.task_id;
            try db.exec(
                \\update state
                \\set
                \\  response_status=?,
                \\  response_ms=?,
                \\  response_body=?,
                \\  response_body_changed=1
            ,
                .{
                    @intFromEnum(resp.status),
                    resp.duration_ms,
                    resp.body,
                },
            );

            try db.execNoArgs("delete from response_headers");
            for (resp.headers) |h| {
                try db.exec(
                    "insert into response_headers (name, value) values (?, ?)",
                    .{ h[0], h[1] },
                );
            }

            try db.exec("delete from task where id=?", .{task_id});
            try db.exec(
                "update state set app_status=?",
                .{
                    try std.fmt.allocPrint(
                        arena,
                        "Finished request (took {s})",
                        .{
                            if (resp.duration_ms >= 1_000)
                                try std.fmt.allocPrint(arena, "{d}s", .{@divTrunc(resp.duration_ms, 1000)})
                            else
                                try std.fmt.allocPrint(arena, "{d} ms", .{resp.duration_ms}),
                        },
                    ),
                },
            );
        },
        .change_response_tab => |tab| {
            try db.exec(
                "update state set resp_active_tab=?",
                .{@tagName(tab)},
            );
        },
    }

    try db.commit();
}
