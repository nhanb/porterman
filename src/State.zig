const std = @import("std");
const Database = @import("./Database.zig");
const enums = @import("./enums.zig");

const State = @This();

method: enums.HttpMethod,
url: []const u8,
sending: bool,
response_status: ?std.http.Status,
response_body: ?[]const u8,
app_status: []const u8,
has_blocking_task: bool,

pub fn fromDb(arena: std.mem.Allocator, db: Database) !State {
    const state_row = (try db.selectRow(
        \\select
        \\  method, url, sending, response_status, response_body, app_status
        \\from state limit 1;
    , .{})).?;
    defer state_row.deinit();

    const num_blocking_tasks = try db.selectInt(
        "select count(*) from task where blocking=1;",
        .{},
    );

    return State{
        .method = std.meta.stringToEnum(
            enums.HttpMethod,
            try arena.dupe(u8, state_row.text(0)),
        ).?,
        .url = try arena.dupe(u8, state_row.text(1)),
        .sending = state_row.int(2) == 1,

        .response_status = if (state_row.nullableInt(3)) |status|
            @enumFromInt(status)
        else
            null,

        .response_body = if (state_row.nullableText(4)) |text|
            try arena.dupe(u8, text)
        else
            null,

        .app_status = try arena.dupe(u8, state_row.text(5)),
        .has_blocking_task = num_blocking_tasks > 0,
    };
}
