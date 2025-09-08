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
            .size = .{ .w = 1920.0, .h = 1080.0 },
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
    try dvui.addFont("NotoSans", @embedFile("./fonts/NotoSans-Regular.ttf"), null);
    try dvui.addFont("NotoSansBold", @embedFile("./fonts/NotoSans-Bold.ttf"), null);

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

const huge_text = @embedFile("./text.txt");

pub fn frame() !dvui.App.Result {
    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
    defer scroll.deinit();

    dvui.labelNoFmt(@src(), huge_text[0..65535], .{}, .{});

    return .ok;
}

test "main" {
    _ = RingBuffer;
}
