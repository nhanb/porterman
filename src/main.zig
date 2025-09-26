const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");

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

// Runs before the first frame, after backend and dvui.Window.init()
// - runs between win.begin()/win.end()
pub fn AppInit(_: *dvui.Window) !void {}

// Run as app is shutting down before dvui.Window.deinit()
pub fn AppDeinit() void {}

// Run each frame to do normal UI
pub fn AppFrame() !dvui.App.Result {
    return frame();
}

var showText = false;

pub fn frame() !dvui.App.Result {
    dvui.refresh(null, @src(), null);

    var vbox = dvui.box(@src(), .{}, .{
        .background = true,
        .style = .window,
        .expand = .both,
    });
    defer vbox.deinit();

    dvui.label(@src(), "{d} fps", .{dvui.FPS()}, .{});

    _ = dvui.checkbox(@src(), &showText, "Show TextLayout", .{});

    if (showText) {
        var scroll = dvui.scrollArea(@src(), .{}, .{});
        defer scroll.deinit();

        const tl = dvui.textLayout(@src(), .{}, .{});
        tl.addText(@embedFile("./text.txt"), .{});
        tl.deinit();
    }
    return .ok;
}

test "main" {}
