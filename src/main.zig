const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
const theme = @import("./theme.zig");
const Database = @import("./Database.zig");
const queue = @import("./queue.zig");

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
    const enum_fields = @typeInfo(HttpMethod).@"enum".fields;
    var names: [enum_fields.len][]const u8 = undefined;
    for (enum_fields, 0..) |field, i| {
        names[i] = field.name;
    }
    break :blk names;
};

const State = struct {
    method: HttpMethod,
    url: []const u8,
    sending: bool,
    response_status: std.http.Status,
    response_body: []const u8,

    pub fn fromDb(arena: std.mem.Allocator, db: Database) !State {
        const row = (try db.selectRow(
            \\select method, url, sending, response_status, response_body
            \\from state limit 1;
        , .{})).?;
        defer row.deinit();

        const status: i64 = @intCast(row.int(3));
        return State{
            .method = std.meta.stringToEnum(
                HttpMethod,
                try arena.dupe(u8, row.text(0)),
            ).?,
            .url = try arena.dupe(u8, row.text(1)),
            .sending = row.int(2) == 1,
            .response_status = @enumFromInt(status),
            .response_body = try arena.dupe(u8, row.text(4)),
        };
    }

    pub fn sendRequest(self: State) !void {
        // Create the client
        var client = std.http.Client{ .allocator = dba };
        defer client.deinit();

        var resp_writer = std.Io.Writer.Allocating.init(dba);
        const url = self.url;

        // Make the request
        const response = try client.fetch(.{
            .method = .GET,
            .location = .{ .url = url },
            .response_writer = &resp_writer.writer,
            .headers = .{
                //.accept_encoding = .{ .override = "application/json" },
            },
        });

        std.log.info(">> {any}: {s}", .{ response.status, resp_writer.written() });
        //self.response_body = resp_writer.written();
        //self.response_status = response.status;
    }
};

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

var dba_impl = std.heap.DebugAllocator(.{}).init;
const dba = dba_impl.allocator();

var frame_arena_impl = std.heap.ArenaAllocator.init(dba);
const frame_arena = frame_arena_impl.allocator();

var database: Database = undefined;

// Runs before the first frame, after backend and dvui.Window.init()
// - runs between win.begin()/win.end()
pub fn AppInit(win: *dvui.Window) !void {
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

    // Init in-memory db that will be the single source of truth for app state
    database = try Database.init();
    try database.execNoArgs(@embedFile("./db-schema.sql"));
}

// Run as app is shutting down before dvui.Window.deinit()
pub fn AppDeinit() void {
    std.log.info("AppDeinit()", .{});
    database.deinit();
}

// Run each frame to do normal UI
pub fn AppFrame() !dvui.App.Result {
    return frame();
}

pub fn frame() !dvui.App.Result {
    defer _ = frame_arena_impl.reset(.retain_capacity);
    const state = try State.fromDb(frame_arena, database);

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
            const new_method: HttpMethod = @enumFromInt(method_choice);
            try database.exec("update state set method=?;", .{@tagName(new_method)});
        }

        // URL input
        var url_entry = dvui.textEntry(
            @src(),
            .{ .text = .{ .internal = .{ .limit = 2048 } }, .placeholder = "enter url here" },
            .{ .expand = .horizontal },
        );
        if (dvui.firstFrame(url_entry.data().id)) {
            const row = (try database.selectRow("select url from state limit 1", .{})).?;
            defer row.deinit();

            url_entry.textSet(row.text(0), false);
            dvui.focusWidget(url_entry.data().id, null, null);
        }
        if (url_entry.text_changed) {
            try database.exec("update state set url=?;", .{url_entry.getText()});
        }
        url_entry.deinit();

        // Go!
        if (theme.button(@src(), "send", state.url.len == 0, .{ .gravity_y = 0.5 })) {
            try state.sendRequest();
        }
    }

    return .ok;
}

test "main" {
    _ = queue;
}
