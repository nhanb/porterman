const std = @import("std");
const Database = @import("./Database.zig");
const enums = @import("./enums.zig");

const State = @This();

method: enums.HttpMethod,
url: []const u8,
sending: bool,
response_status: ?std.http.Status,
response_body: ?[]const u8,
blocking_task: ?enums.Task,
app_status: []const u8,

pub fn fromDb(arena: std.mem.Allocator, db: Database) !State {
    const row = (try db.selectRow(
        \\select
        \\  method, url, sending, response_status, response_body, blocking_task,
        \\  app_status
        \\from state limit 1;
    , .{})).?;
    defer row.deinit();

    return State{
        .method = std.meta.stringToEnum(
            enums.HttpMethod,
            try arena.dupe(u8, row.text(0)),
        ).?,
        .url = try arena.dupe(u8, row.text(1)),
        .sending = row.int(2) == 1,

        .response_status = if (row.nullableInt(3)) |status|
            @enumFromInt(status)
        else
            null,

        .response_body = if (row.nullableText(4)) |text|
            try arena.dupe(u8, text)
        else
            null,

        .blocking_task = if (row.nullableText(5)) |task_str|
            std.meta.stringToEnum(enums.Task, task_str)
        else
            null,

        .app_status = try arena.dupe(u8, row.text(6)),
    };
}
