const std = @import("std");
const Allocator = std.mem.Allocator;
const dvui = @import("dvui");
const enums = @import("enums.zig");
const HttpMethod = enums.HttpMethod;
const RingBuffer = @import("queue.zig").RingBuffer;

pub const MessageType = enum {
    response_received,
};

pub const Message = union(MessageType) {
    response_received: struct {
        status: std.http.Status,
        body: []const u8,
    },

    pub fn init(gpa: Allocator, msg_type: MessageType, data: anytype) Message {
        return switch (msg_type) {
            .response_received => Message{ .response_received = .{
                .status = data.status,
                .body = gpa.dupe(u8, data.body) catch @panic("Out of memory."),
            } },
        };
    }

    pub fn deinit(self: Message, gpa: Allocator) void {
        switch (self) {
            .response_received => {
                gpa.free(self.response_received.body);
            },
        }
    }
};

pub fn sendRequest(
    gpa: std.mem.Allocator,
    win: *dvui.Window,
    method: HttpMethod,
    url: []const u8,
    msg_queue: *RingBuffer(Message, 100),
) !void {
    var response: std.Io.Writer.Allocating = .init(gpa);
    defer response.deinit();

    var client: std.http.Client = .{ .allocator = gpa };
    defer client.deinit();

    const std_method: std.http.Method = std.meta.stringToEnum(
        std.http.Method,
        @tagName(method),
    ).?;

    const result = try client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &response.writer,
        .headers = .{},
        .method = std_method,
    });

    _ = msg_queue.push(Message.init(
        gpa,
        .response_received,
        .{ .status = result.status, .body = response.written() },
    )).?;

    dvui.refresh(win, @src(), null);
}
