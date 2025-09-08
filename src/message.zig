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

    pub fn deinit(self: *Message, gpa: Allocator) void {
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
    // Create the client
    var client = std.http.Client{ .allocator = gpa };
    defer client.deinit();

    var resp_writer = std.Io.Writer.Allocating.init(gpa);

    std.log.info("sendRequest: {any} {s}", .{ method, url });

    // Make the request

    const std_method: std.http.Method = std.meta.stringToEnum(
        std.http.Method,
        @tagName(method),
    ).?;

    const response = try client.fetch(.{
        .method = std_method,
        .location = .{ .url = url },
        .response_writer = &resp_writer.writer,
        .headers = .{
            //.accept_encoding = .{ .override = "application/json" },
        },
    });

    _ = msg_queue.push(Message.init(
        gpa,
        .response_received,
        .{ .status = response.status, .body = resp_writer.written() },
    )).?;

    dvui.refresh(win, @src(), null);
}
