const std = @import("std");
const Allocator = std.mem.Allocator;
const dvui = @import("dvui");
const enums = @import("enums.zig");
const Database = @import("Database.zig");

pub fn sendRequest(
    gpa: std.mem.Allocator,
    win: *dvui.Window,
    task_id: i64,
) !void {
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

    var response: std.Io.Writer.Allocating = .init(gpa);
    defer response.deinit();

    var client: std.http.Client = .{ .allocator = gpa };
    defer client.deinit();

    const result = try client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &response.writer,
        .headers = .{},
        .method = http_method,
    });

    try db.begin();
    errdefer db.rollback();

    try db.exec(
        "update state set response_status=?, response_body=?",
        .{ @intFromEnum(result.status), response.written() },
    );
    try db.exec("delete from task where id=?", .{task_id});
    try db.execNoArgs("update state set app_status='Finished request'");
    try db.commit();

    dvui.refresh(win, @src(), null);
}
