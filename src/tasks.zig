const std = @import("std");
const Allocator = std.mem.Allocator;
const dvui = @import("dvui");
const enums = @import("enums.zig");
const Database = @import("Database.zig");
const curl = @import("curl.zig");
const core = @import("core.zig");

const log = std.log.scoped(.tasks);

pub fn sendRequest(
    gpa: std.mem.Allocator,
    win: *dvui.Window,
    task_id: i64,
) !void {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    const arena = arena_state.allocator();
    defer arena_state.deinit();

    const db = try Database.init();

    var http_method: std.http.Method = undefined;
    var url: []const u8 = undefined;

    {
        try db.begin();
        errdefer db.rollback();

        const row = (try db.selectRow(
            \\select
            \\  data ->> '$.method',
            \\  data ->> '$.url'
            \\from task where id=?
        ,
            .{task_id},
        )).?;
        defer row.deinit();

        http_method = std.meta.stringToEnum(std.http.Method, row.text(0)).?;
        url = try arena.dupe(u8, row.text(1));

        try db.commit();
    }

    const resp = try curl.get(arena, url);
    try core.exec(gpa, arena, win, db, .{ .finish_request = .{
        .task_id = task_id,
        .curl_response = resp,
    } });

    dvui.refresh(win, @src(), null);
}
