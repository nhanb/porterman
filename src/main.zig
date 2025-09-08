const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
const theme = @import("./theme.zig");
const Database = @import("./Database.zig");
const RingBuffer = @import("./queue.zig").RingBuffer;
const message = @import("./message.zig");
const State = @import("./State.zig");
const enums = @import("./enums.zig");

pub const http_method_names = blk: {
    const enum_fields = @typeInfo(enums.HttpMethod).@"enum".fields;
    var names: [enum_fields.len][]const u8 = undefined;
    for (enum_fields, 0..) |field, i| {
        names[i] = field.name;
    }
    break :blk names;
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

var gpa_impl = std.heap.DebugAllocator(.{}).init;
const gpa = gpa_impl.allocator();

var frame_arena_impl = std.heap.ArenaAllocator.init(gpa);
const frame_arena = frame_arena_impl.allocator();

var database: Database = undefined;
var messages: RingBuffer(message.Message, 100) = .{};

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
    const win = dvui.currentWindow();

    // Handle messages sent back from off-thread tasks
    while (messages.pop()) |msg| {
        switch (msg) {
            .response_received => |data| {
                try database.exec(
                    "update state set response_status=?, response_body=?",
                    .{ @intFromEnum(data.status), data.body },
                );

                if (state.blocking_task) |task| {
                    if (task == .send_request) {
                        try database.execNoArgs(
                            \\update state set
                            \\  blocking_task=null,
                            \\  app_status='Finished request';
                        );
                    }
                }
            },
        }

        // Request another frame so that the latest changes made to the db
        // are loaded into State.
        dvui.refresh(null, @src(), null);
    }

    // Handle global events
    const evts = dvui.events();
    event_handling: for (evts) |*e| {
        if (state.blocking_task) |_| {
            // TODO: show current blocking task in a status label or something
            break :event_handling;
        }

        switch (e.evt) {
            .key => |key| {
                if (key.action == .down) {
                    // TODO: refactor repeated event handling code
                    if (key.matchBind("ptm_send_request")) {
                        try database.exec(
                            \\update state set
                            \\  blocking_task=?,
                            \\  app_status='Sending request...';
                        ,
                            .{@tagName(enums.Task.send_request)},
                        );

                        _ = try std.Thread.spawn(
                            .{},
                            message.sendRequest,
                            .{ gpa, win, state.method, state.url, &messages },
                        );
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
            const new_method: enums.HttpMethod = @enumFromInt(method_choice);
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
        if (theme.button(
            @src(),
            "send",
            state.blocking_task != null or state.url.len == 0,
            .{ .gravity_y = 0.5 },
        )) {
            try database.exec(
                \\update state set
                \\  blocking_task=?,
                \\  app_status='Sending request...';
            ,
                .{@tagName(enums.Task.send_request)},
            );

            _ = try std.Thread.spawn(
                .{},
                message.sendRequest,
                .{ gpa, win, state.method, state.url, &messages },
            );
        }
    }

    if (state.response_status) |status| {
        dvui.label(
            @src(),
            "Response status: {d} {s}",
            .{
                status,
                if (status.phrase()) |phrase| phrase else "",
            },
            .{},
        );

        dvui.label(@src(), "Response body:", .{}, .{});
        {
            var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
            defer scroll.deinit();

            var resp_tl = dvui.textLayout(@src(), .{}, .{ .expand = .both });
            resp_tl.addText(state.response_body.?, .{});
            resp_tl.deinit();
        }
    }

    dvui.labelNoFmt(
        @src(),
        state.app_status,
        .{},
        .{ .gravity_x = 1, .gravity_y = 1 },
    );

    return .ok;
}

test "main" {
    _ = RingBuffer;
}
