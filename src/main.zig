const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
const zqlite = @import("zqlite");
const theme = @import("./theme.zig");
const Database = @import("./Database.zig");
const tasks = @import("./tasks.zig");
const State = @import("./State.zig");
const core = @import("./core.zig");
const enums = @import("./enums.zig");
const curl = @import("./curl.zig");

const log = std.log.scoped(.main);

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
            .size = .{ .w = 800, .h = 600 },
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

var db: Database = undefined;

// Runs before the first frame, after backend and dvui.Window.init()
// - runs between win.begin()/win.end()
pub fn AppInit(win: *dvui.Window) !void {
    try curl.init();

    theme.initDefaults();

    try dvui.addFont("SourceSans", @embedFile("./fonts/SourceSans3-Regular.ttf"), null);
    try dvui.addFont("SourceSansBold", @embedFile("./fonts/SourceSans3-Bold.ttf"), null);
    try dvui.addFont("SourceCodePro", @embedFile("./fonts/SourceCodePro-Regular.ttf"), null);
    try dvui.addFont("SourceCodeProBold", @embedFile("./fonts/SourceCodePro-Bold.ttf"), null);

    // Extra keybinds
    try win.keybinds.putNoClobber(win.gpa, "ptm_send_request", switch (builtin.target.os.tag) {
        .macos => dvui.enums.Keybind{ .command = true, .key = .enter },
        else => dvui.enums.Keybind{ .control = true, .key = .enter },
    });

    // Init in-memory db that will be the single source of truth for app state
    db = try Database.init();
    try db.execNoArgs(@embedFile("./db-schema.sql"));
}

// Run as app is shutting down before dvui.Window.deinit()
pub fn AppDeinit() void {
    log.info("AppDeinit()", .{});
    db.deinit();
    curl.deinit();
}

// Run each frame to do normal UI
pub fn AppFrame() !dvui.App.Result {
    defer _ = frame_arena_impl.reset(.retain_capacity);
    const state = try State.fromDb(frame_arena, db);
    const win = dvui.currentWindow();

    // React to changes in dark mode preference in real time.
    // Not sure how costly this is, so move it to AppInit() if it's a problem.
    win.theme = switch (win.backend.preferredColorScheme() orelse .light) {
        .light => theme.light,
        .dark => theme.dark,
    };

    // Handle global events
    const evts = dvui.events();
    event_handling: for (evts) |*e| {
        if (state.has_blocking_task) {
            break :event_handling;
        }

        switch (e.evt) {
            .key => |key| {
                if (key.action == .down) {
                    if (key.matchBind("ptm_send_request")) {
                        try core.exec(
                            gpa,
                            frame_arena,
                            win,
                            db,
                            .{
                                .start_request = .{
                                    .url = state.url,
                                    .method = state.method,
                                },
                            },
                        );

                        // Don't leak this event to control widgets
                        e.handle(@src(), win.data());
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
        var bottom_hbox = dvui.box(
            @src(),
            .{ .dir = .horizontal },
            .{
                .gravity_y = 1,
                .expand = .horizontal,
                .border = .{ .y = 1 },
                .style = .window,
                .background = true,
            },
        );
        defer bottom_hbox.deinit();

        dvui.label(@src(), "{d} fps", .{@round(dvui.FPS())}, .{});

        dvui.labelNoFmt(
            @src(),
            state.app_status,
            .{},
            .{ .gravity_x = 1 },
        );
    }

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
            try core.exec(gpa, frame_arena, win, db, .{ .change_method = new_method });
        }

        // URL input
        var url_entry = dvui.textEntry(
            @src(),
            .{ .text = .{ .internal = .{ .limit = 2048 } }, .placeholder = "enter url here" },
            .{ .expand = .horizontal },
        );
        if (dvui.firstFrame(url_entry.data().id)) {
            url_entry.textSet(state.url, false);
            dvui.focusWidget(url_entry.data().id, null, null);
        }
        if (url_entry.text_changed) {
            const url = url_entry.getText();
            try core.exec(gpa, frame_arena, win, db, .{ .change_url = url });
        }
        url_entry.deinit();

        // Go!
        if (theme.button(
            @src(),
            "send",
            state.has_blocking_task or state.url.len == 0,
            .{ .gravity_y = 0.5 },
        )) {
            try core.exec(
                gpa,
                frame_arena,
                win,
                db,
                .{
                    .start_request = .{
                        .url = state.url,
                        .method = state.method,
                    },
                },
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

        var tbox = dvui.box(@src(), .{}, .{ .expand = .both });
        defer tbox.deinit();
        {
            var tabs = dvui.tabs(
                @src(),
                .{ .dir = .horizontal },
                .{ .expand = .horizontal },
            );
            defer tabs.deinit();
            for (0..State.ResponseTab.len) |tab_num| {
                const this_tab: State.ResponseTab = @enumFromInt(tab_num);
                const selected = state.resp_active_tab == this_tab;

                var tab = tabs.addTab(selected, .{
                    .font = win.theme.font_body,
                    .border = .{ .x = 1, .y = 1, .w = 1 },
                    .color_fill_hover = if (selected) win.theme.window.fill else null,
                });
                defer tab.deinit();

                var label_opts = tab.data().options.strip();
                if (dvui.captured(tab.data().id)) {
                    label_opts.color_text = label_opts.color(.text_press);
                }

                dvui.labelNoFmt(@src(), State.resp_tab_label(this_tab), .{}, label_opts);

                if (tab.clicked()) {
                    try core.exec(
                        gpa,
                        frame_arena,
                        win,
                        db,
                        .{ .change_response_tab = this_tab },
                    );
                }
            }
        }

        switch (state.resp_active_tab) {
            .body => {
                var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
                defer scroll.deinit();

                var body_text = dvui.textLayout(
                    @src(),
                    .{ .break_lines = true, .cache_layout = !state.response_body_changed },
                    .{ .expand = .both, .font = win.theme.font_title_4, .background = false },
                );
                body_text.addText(state.response_body.?, .{});
                body_text.deinit();
            },

            .headers => {
                var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
                defer scroll.deinit();

                var headers_text = dvui.textLayout(
                    @src(),
                    .{ .break_lines = true, .cache_layout = !state.response_body_changed },
                    .{ .expand = .both, .font = win.theme.font_title_4, .background = false },
                );
                for (state.response_headers) |h| {
                    const name = h[0];
                    const value = h[1];
                    headers_text.addText(name, .{ .font = win.theme.font_title_3 });
                    headers_text.addText(": ", .{ .font = win.theme.font_title_3 });
                    headers_text.addText(value, .{});
                    headers_text.addText("\n", .{});
                }
                headers_text.deinit();
            },
        }
    }

    if (state.response_body_changed) {
        try db.execNoArgs("update state set response_body_changed=0;");
    }

    //dvui.refresh(win, @src(), null);
    return .ok;
}

test "main" {}
