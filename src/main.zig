const std = @import("std");
const dvui = @import("dvui");

// To be a dvui App:
// * declare "dvui_app"
// * expose the backend's main function
// * use the backend's log function
pub const dvui_app: dvui.App = .{
    .config = .{
        .options = .{
            .size = .{ .w = 800.0, .h = 600.0 },
            .min_size = .{ .w = 250.0, .h = 350.0 },
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

var gpa_instance = std.heap.DebugAllocator(.{}).init();
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
}

// Run as app is shutting down before dvui.Window.deinit()
pub fn AppDeinit() void {}

// Run each frame to do normal UI
pub fn AppFrame() !dvui.App.Result {
    return frame();
}

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

const State = struct {
    method: HttpMethod = .GET,
    url: struct {
        buf: [2048]u8 = undefined, // https://stackoverflow.com/a/417184
        len: usize = 0,
    } = .{},
};
var state = State{};

pub fn frame() !dvui.App.Result {
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
        const method_enum_fields = @typeInfo(HttpMethod).@"enum".fields;
        const method_choices: [method_enum_fields.len][]const u8 = blk: {
            var results: [method_enum_fields.len][]const u8 = undefined;
            inline for (method_enum_fields, 0..) |field, i| {
                results[i] = field.name;
            }
            break :blk results;
        };
        var method_choice: usize = @intFromEnum(state.method);
        if (dvui.dropdown(
            @src(),
            &method_choices,
            &method_choice,
            .{ .min_size_content = .{ .w = 100 }, .gravity_y = 0.5 },
        )) {
            state.method = @enumFromInt(method_choice);
        }

        // URL input
        var url_entry = dvui.textEntry(
            @src(),
            .{
                .text = .{
                    .buffer = &state.url.buf,
                },
            },
            .{ .expand = .horizontal },
        );
        if (dvui.firstFrame(url_entry.data().id)) {
            url_entry.textSet(state.url.buf[0..state.url.len], false);
        }
        state.url.len = url_entry.len;
        defer url_entry.deinit();
    }

    return .ok;
}
