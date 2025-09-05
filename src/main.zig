const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
const theme = @import("./theme.zig");

const HttpMethod = enum {
    GET,
    HEAD,
    POST,
    PUT,
    DELETE,
    OPTIONS,
    TRACE,
    PATCH,
};
const http_method_names = blk: {
    const method_enum_fields = @typeInfo(HttpMethod).@"enum".fields;
    var results: [method_enum_fields.len][]const u8 = undefined;
    for (method_enum_fields, 0..) |field, i| {
        results[i] = field.name;
    }
    break :blk results;
};

const State = struct {
    method: HttpMethod = .GET,
    url: struct {
        // max practical URL size is 2000:
        // https://stackoverflow.com/a/417184
        buf: [2048]u8 = std.mem.zeroes([2048]u8),
        len: usize = 0,

        fn getText(self: *@This()) []const u8 {
            return self.buf[0..self.len];
        }
        fn setText(self: *@This(), text: []const u8) void {
            @memcpy(self.buf[0..text.len], text);
            self.len = text.len;
        }
    } = .{},

    pub fn sendRequest(self: *State) !void {
        // Create the client
        var client = std.http.Client{ .allocator = gpa };
        defer client.deinit();

        var resp_writer = std.Io.Writer.Allocating.init(gpa);
        const url = self.url.getText();

        // Make the request
        const response = try client.fetch(.{
            .method = .GET,
            .location = .{ .url = url },
            .response_writer = &resp_writer.writer,
            .headers = .{
                //.accept_encoding = .{ .override = "application/json" },
            },
        });

        // Do whatever you need to in case of HTTP error.
        if (response.status != .ok) {
            @panic("Handle errors");
        }

        std.log.info(">> {s}", .{resp_writer.written()});
    }
};
var state = State{};

// To be a dvui App:
// * declare "dvui_app"
// * expose the backend's main function
// * use the backend's log function
pub const dvui_app: dvui.App = .{
    .config = .{
        .options = .{
            .size = .{ .w = 600.0, .h = 250.0 },
            .min_size = .{ .w = 400.0, .h = 250.0 },
            .title = "Porterman",
            .window_init_options = .{
                // Could set a default theme here
                // .theme = dvui.Theme.builtin.dracula,
            },
        },
    },
    .frameFn = AppFrame,
    .initFn = AppInit,
    .deinitFn = AppDeinit,
};
pub const main = dvui.App.main;
pub const panic = dvui.App.panic;
pub const std_options: std.Options = .{
    .logFn = dvui.App.logFn,
};

var gpa_instance = std.heap.DebugAllocator(.{}).init;
const gpa = gpa_instance.allocator();

var orig_content_scale: f32 = 1.0;

// Runs before the first frame, after backend and dvui.Window.init()
// - runs between win.begin()/win.end()
pub fn AppInit(win: *dvui.Window) !void {
    orig_content_scale = win.content_scale;
    //try dvui.addFont("NOTO", @embedFile("../src/fonts/NotoSansKR-Regular.ttf"), null);

    // If you need to set a theme based on the users preferred color scheme, do it here
    win.theme = switch (win.backend.preferredColorScheme() orelse .light) {
        .light => dvui.Theme.builtin.adwaita_light,
        .dark => dvui.Theme.builtin.adwaita_dark,
    };

    // Extra keybinds
    try win.keybinds.putNoClobber(win.gpa, "ptm_send_request", switch (builtin.target.os.tag) {
        .macos => dvui.enums.Keybind{ .command = true, .key = .enter },
        else => dvui.enums.Keybind{ .control = true, .key = .enter },
    });

    state.url.setText("https://httpbin.org/headers");
}

// Run as app is shutting down before dvui.Window.deinit()
pub fn AppDeinit() void {}

// Run each frame to do normal UI
pub fn AppFrame() !dvui.App.Result {
    return frame();
}

pub fn frame() !dvui.App.Result {
    // Handle global events
    const evts = dvui.events();
    for (evts) |*e| {
        switch (e.evt) {
            .key => |key| {
                if (key.action == .down) {
                    //std.log.info(">> key down: {s}", .{@tagName(key.code)});
                    if (key.matchBind("ptm_send_request")) {
                        try state.sendRequest();
                    }
                }
            },
            else => {},
        }
    }

    // GUI starts here

    var vbox = dvui.box(
        @src(),
        .{ .dir = .vertical },
        .{ .style = .window, .background = true, .expand = .both },
    );
    defer vbox.deinit();

    {
        var hbox = dvui.box(
            @src(),
            .{ .dir = .horizontal },
            .{ .style = .window, .expand = .horizontal },
        );
        defer hbox.deinit();

        // HTTP method dropdown
        var method_choice: usize = @intFromEnum(state.method);
        if (dvui.dropdown(
            @src(),
            &http_method_names,
            &method_choice,
            .{ .min_size_content = .{ .w = 100 }, .gravity_y = 0.5 },
        )) {
            state.method = @enumFromInt(method_choice);
        }

        // URL input
        var url_entry = dvui.textEntry(
            @src(),
            .{ .text = .{ .buffer = &state.url.buf }, .placeholder = "enter url here" },
            .{ .expand = .horizontal },
        );
        if (dvui.firstFrame(url_entry.data().id)) {
            url_entry.textSet(state.url.buf[0..state.url.len], false);
            dvui.focusWidget(url_entry.data().id, null, null);
        }
        state.url.len = url_entry.len;
        url_entry.deinit();

        // Go!
        if (theme.button(@src(), "send", state.url.len == 0, .{ .gravity_y = 0.5 })) {
            try state.sendRequest();
        }
    }

    return .ok;
}
