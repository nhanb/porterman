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

    _ = http_method;
    const result = try curl.get(gpa, url, &response.writer);

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
