const std = @import("std");
const Database = @import("./Database.zig");
const enums = @import("./enums.zig");

const State = @This();

method: enums.HttpMethod,
url: []const u8,
sending: bool,
response_status: std.http.Status,
response_body: []const u8,
blocking_task: ?enums.Task,

pub fn fromDb(arena: std.mem.Allocator, db: Database) !State {
    const row = (try db.selectRow(
        \\select method, url, sending, response_status, response_body, blocking_task
        \\from state limit 1;
    , .{})).?;
    defer row.deinit();

    const status: i64 = @intCast(row.int(3));
    return State{
        .method = std.meta.stringToEnum(
            enums.HttpMethod,
            try arena.dupe(u8, row.text(0)),
        ).?,
        .url = try arena.dupe(u8, row.text(1)),
        .sending = row.int(2) == 1,
        .response_status = @enumFromInt(status),
        .response_body = try arena.dupe(u8, row.text(4)),
        .blocking_task = if (row.nullableText(5)) |task_str|
            std.meta.stringToEnum(enums.Task, task_str)
        else
            null,
    };
}
