const std = @import("std");
const Database = @import("./Database.zig");
const enums = @import("./enums.zig");

const State = @This();

method: enums.HttpMethod,
url: []const u8,
sending: bool,
response_status: ?std.http.Status,
response_body: ?[]const u8,
response_body_changed: bool,
response_headers: []const [2][]const u8,
app_status: []const u8,
has_blocking_task: bool,

resp_active_tab: ResponseTab,

pub const ResponseTab = enum {
    body,
    headers,
    pub const len = @typeInfo(@This()).@"enum".fields.len;
};

pub fn resp_tab_label(tab: ResponseTab) []const u8 {
    return switch (tab) {
        .body => "Body",
        .headers => "Headers",
    };
}

pub fn fromDb(arena: std.mem.Allocator, db: Database) !State {
    // Simple key-val states
    const state_row = (try db.selectRow(
        \\select
        \\  method, url, sending, response_status, response_body,
        \\  response_body_changed, app_status, resp_active_tab
        \\from state limit 1;
    , .{})).?;
    defer state_row.deinit();

    // Blocking, long-running tasks
    const num_blocking_tasks = try db.selectInt(
        "select count(*) from task where blocking=1;",
        .{},
    );

    // Headers
    var resp_headers = try std.ArrayList([2][]u8).initCapacity(arena, 32);
    {
        var rows = try db.rows("select name, value from response_headers order by id", .{});
        defer rows.deinit();
        while (rows.next()) |row| {
            const name = try arena.dupe(u8, row.text(0));
            const value = try arena.dupe(u8, row.text(1));
            try resp_headers.append(arena, .{ name, value });
        }
        if (rows.err) |err| return err;
    }

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

        .response_body_changed = state_row.int(5) == 1,
        .response_headers = resp_headers.items,
        .app_status = try arena.dupe(u8, state_row.text(6)),
        .has_blocking_task = num_blocking_tasks > 0,
        .resp_active_tab = std.meta.stringToEnum(ResponseTab, state_row.text(7)).?,
    };
}
