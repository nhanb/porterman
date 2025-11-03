const std = @import("std");
const mem = std.mem;
const Io = std.Io;
const c = @cImport({
    @cInclude("curl/curl.h");
});

pub const Response = struct {
    status: std.http.Status,
    headers: []const [2][]const u8, // non-unique key-value pairs
};

pub fn init() !void {
    if (c.curl_global_init(c.CURL_GLOBAL_ALL) != c.CURLE_OK)
        return error.CURLGlobalInitFailed;
}

pub fn deinit() void {
    c.curl_global_cleanup();
}

pub fn get(arena: mem.Allocator, url: []const u8, writer: *Io.Writer) !Response {
    std.log.info("GET {s}", .{url});

    // curl easy handle init, or fail
    const handle = c.curl_easy_init() orelse return error.CURLHandleInitFailed;
    defer c.curl_easy_cleanup(handle);

    // setup curl options
    if (c.curl_easy_setopt(handle, c.CURLOPT_URL, url.ptr) != c.CURLE_OK)
        return error.CouldNotSetURL;

    // set write function callbacks
    if (c.curl_easy_setopt(handle, c.CURLOPT_WRITEFUNCTION, writeToArrayListCallback) != c.CURLE_OK)
        return error.CouldNotSetWriteCallback;

    if (c.curl_easy_setopt(handle, c.CURLOPT_WRITEDATA, writer) != c.CURLE_OK)
        return error.CouldNotSetWriteCallback;

    if (c.curl_easy_setopt(handle, c.CURLOPT_ACCEPT_ENCODING, "zstd, br, gzip") != c.CURLE_OK)
        return error.CouldNotSetEncoding;

    // perform request
    const result = c.curl_easy_perform(handle);
    if (result != c.CURLE_OK) {
        std.log.err("curl_easy_perform failed: {d}", .{result});
        return error.FailedToPerformRequest;
    }

    var status: c_uint = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_RESPONSE_CODE, &status) != c.CURLE_OK)
        return error.FailedToGetResponseCode;
    std.log.info("Resp status: {d}", .{status});

    var c_content_type: [*:0]const u8 = undefined;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_CONTENT_TYPE, &c_content_type) != c.CURLE_OK)
        return error.FailedToGetContentType;

    // read headers
    var headers = try std.ArrayList([2][]u8).initCapacity(arena, 32);

    var prev: ?*c.curl_header = null;
    while (true) {
        if (c.curl_easy_nextheader(handle, c.CURLH_HEADER, -1, prev)) |h| {
            const name = try arena.dupe(u8, mem.span(h.*.name));
            const value = try arena.dupe(u8, mem.span(h.*.value));
            try headers.append(arena, .{ name, value });
            prev = h;
        } else {
            break;
        }
    }

    for (headers.items) |h| {
        std.log.info("Header: {s}: {s}", .{ h[0], h[1] });
    }

    std.log.info("Resp content-type: {s}", .{c_content_type});

    std.log.info("Got response of {d} bytes", .{writer.buffered().len});

    return Response{ .status = .ok, .headers = headers.items };
}

fn writeToArrayListCallback(data: *anyopaque, size: c_uint, nmemb: c_uint, user_data: *anyopaque) callconv(.c) c_uint {
    const writer: *Io.Writer = @ptrCast(@alignCast(user_data));
    var typed_data: [*]u8 = @ptrCast(data);
    writer.writeAll(typed_data[0 .. nmemb * size]) catch @panic("Out of memory or something");
    return nmemb * size;
}
