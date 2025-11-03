const std = @import("std");
const mem = std.mem;
const Io = std.Io;
const c = @cImport({
    @cInclude("curl/curl.h");
});

const log = std.log.scoped(.curl);

pub const Response = struct {
    status: std.http.Status,
    headers: []const [2][]const u8, // non-unique key-value pairs
    body: []const u8,
};

pub fn init() !void {
    if (c.curl_global_init(c.CURL_GLOBAL_ALL) != c.CURLE_OK)
        return error.CURLGlobalInitFailed;
}

pub fn deinit() void {
    c.curl_global_cleanup();
}

pub fn get(arena: mem.Allocator, url: []const u8) !Response {
    log.debug("GET {s}", .{url});

    var resp_body: std.Io.Writer.Allocating = .init(arena);

    // curl easy handle init, or fail
    const handle = c.curl_easy_init() orelse return error.CURLHandleInitFailed;
    defer c.curl_easy_cleanup(handle);

    // setup curl options
    if (c.curl_easy_setopt(handle, c.CURLOPT_URL, url.ptr) != c.CURLE_OK)
        return error.CouldNotSetURL;

    // set write function callbacks
    if (c.curl_easy_setopt(handle, c.CURLOPT_WRITEFUNCTION, writeToArrayListCallback) != c.CURLE_OK)
        return error.CouldNotSetWriteCallback;

    if (c.curl_easy_setopt(handle, c.CURLOPT_WRITEDATA, &resp_body.writer) != c.CURLE_OK)
        return error.CouldNotSetWriteCallback;

    if (c.curl_easy_setopt(handle, c.CURLOPT_ACCEPT_ENCODING, "zstd, br, gzip") != c.CURLE_OK)
        return error.CouldNotSetEncoding;

    // perform request
    const result = c.curl_easy_perform(handle);
    if (result != c.CURLE_OK) {
        log.err("curl_easy_perform failed: {d}", .{result});
        return error.FailedToPerformRequest;
    }

    var status: c_uint = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_RESPONSE_CODE, &status) != c.CURLE_OK)
        return error.FailedToGetResponseCode;
    log.debug("Resp status: {d}", .{status});

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

    return Response{
        .status = .ok,
        .headers = headers.items,
        .body = resp_body.written(),
    };
}

fn writeToArrayListCallback(data: *anyopaque, size: c_uint, nmemb: c_uint, user_data: *anyopaque) callconv(.c) c_uint {
    const writer: *Io.Writer = @ptrCast(@alignCast(user_data));
    var typed_data: [*]u8 = @ptrCast(data);
    writer.writeAll(typed_data[0 .. nmemb * size]) catch @panic("Out of memory or something");
    return nmemb * size;
}
