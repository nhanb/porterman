const std = @import("std");
const fs = std.fs;
const zqlite = @import("zqlite");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.Database);

const Database = @This();

conn: zqlite.Conn,

pub fn init() !Database {
    const flags = zqlite.OpenFlags.Create | zqlite.OpenFlags.EXResCode | zqlite.OpenFlags.Uri;
    // The memdb VFS enables an in-memory DB that's shareable between threads,
    // apparently recommended by drh himself although under-documented:
    // https://sqlite.org/forum/forumpost/0359b21d172bd965
    const conn = try zqlite.open("file:/portermandb?vfs=memdb", flags);
    const db = Database{ .conn = conn };
    try db.execNoArgs(
        \\PRAGMA foreign_keys = 1;
        \\PRAGMA busy_timeout = 5000;
    );
    return db;
}

pub fn save(self: Database, path: [*:0]const u8) !void {
    var tmp_path_buf: [4096]u8 = undefined;
    const tmp_path = try std.fmt.bufPrintZ(&tmp_path_buf, "{s}.tmp", .{path});

    const flags = zqlite.OpenFlags.Create | zqlite.OpenFlags.EXResCode;
    const toConn = try zqlite.open(tmp_path, flags);
    const fromConn = self.conn;
    const pBackup = zqlite.c.sqlite3_backup_init(
        @ptrCast(toConn.conn),
        "main",
        @ptrCast(fromConn.conn),
        "main",
    );
    std.debug.assert(pBackup != null);
    _ = zqlite.c.sqlite3_backup_step(pBackup, -1);
    _ = zqlite.c.sqlite3_backup_finish(pBackup);
    std.debug.assert(zqlite.c.sqlite3_errcode(@ptrCast(toConn.conn)) == zqlite.c.SQLITE_OK);
    toConn.close();

    try std.fs.cwd().renameZ(tmp_path, path);
}

pub fn deinit(self: Database) void {
    self.conn.close();
}

pub fn begin(self: Database) !void {
    try self.conn.execNoArgs("begin exclusive");
}

pub fn commit(self: Database) !void {
    try self.conn.execNoArgs("commit");
}

pub fn rollback(self: Database) void {
    self.conn.execNoArgs("rollback") catch {};
}

pub fn exec(self: Database, sql: []const u8, args: anytype) !void {
    self.conn.exec(sql, args) catch |err| {
        std.log.err("sql: {s}", .{self.conn.lastError()});
        return err;
    };
}

pub fn execNoArgs(self: Database, sql: [*:0]const u8) !void {
    self.conn.execNoArgs(sql) catch |err| {
        std.log.err("sql: {s}", .{self.conn.lastError()});
        return err;
    };
}

pub fn selectRow(self: Database, sql: []const u8, args: anytype) !?zqlite.Row {
    return (self.conn.row(sql, args) catch |err| {
        std.log.err("sql: {s}", .{self.conn.lastError()});
        return err;
    });
}

/// Assumes the result is only 1 row with 1 column, which is an int.
pub fn selectInt(self: Database, sql: []const u8, args: anytype) !i64 {
    var row = (self.conn.row(sql, args) catch |err| {
        std.log.err("sql: {s}", .{self.conn.lastError()});
        return err;
    }).?;
    defer row.deinit();
    return row.int(0);
}

/// Assumes the result is only 1 row with 1 column, which is a text column.
pub fn selectText(self: Database, arena: Allocator, sql: []const u8) !i64 {
    var row = (self.conn.row(sql, .{}) catch |err| {
        std.log.err("sql: {s}", .{self.conn.lastError()});
        return err;
    }).?;
    defer row.deinit();
    return arena.dupe(u8, row.int(0));
}

pub fn rows(self: Database, sql: []const u8, args: anytype) !zqlite.Rows {
    return self.conn.rows(sql, args);
}
