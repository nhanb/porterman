const std = @import("std");
const dvui = @import("dvui");
const Rect = dvui.Rect;
const Color = dvui.Color;

/// Thin wrapper to easily toggle button's disabled state.
/// It adds the necessary styling, and always returns false when disabled.
pub fn button(
    src: std.builtin.SourceLocation,
    label_str: []const u8,
    disabled: bool,
    opts: dvui.Options,
) bool {
    var opts2 = opts;
    if (disabled) {
        // blend text and control colors
        opts2.color_text = dvui.Color.average(opts2.color(.text), opts2.color(.fill));
        opts2.tab_index = 0;
    }
    var bw = dvui.ButtonWidget.init(src, .{}, opts2);
    defer bw.deinit();
    bw.install();
    if (!disabled)
        bw.processEvents();
    bw.drawBackground();
    bw.drawFocus();

    const inner_opts = bw.data().options.strip().override(.{ .gravity_y = 0.5 });

    var bbox = dvui.box(src, .{ .dir = .horizontal }, inner_opts);
    defer bbox.deinit();

    dvui.labelNoFmt(src, label_str, .{}, inner_opts);

    return !disabled and bw.clicked();
}

pub const light = blk: {
    var theme = dvui.Theme.builtin.adwaita_light;
    // TODO: customize here
    applyCommonOpts(&theme);
    break :blk theme;
};

pub const dark = blk: {
    var theme = dvui.Theme.builtin.adwaita_dark;
    // TODO: customize here
    applyCommonOpts(&theme);
    break :blk theme;
};

fn applyCommonOpts(theme: *dvui.Theme) void {
    theme.font_body.id = .fromName("NotoSans");
    theme.font_body.size = 18;
}

pub fn initDefaults() void {
    const corner_radius = Rect.all(0);
    dvui.ButtonWidget.defaults.corner_radius = corner_radius;
    dvui.DropdownWidget.defaults.corner_radius = corner_radius;
    dvui.TextEntryWidget.defaults.corner_radius = corner_radius;
    dvui.FloatingMenuWidget.defaults.corner_radius = corner_radius;
    dvui.ScrollAreaWidget.defaults.corner_radius = corner_radius;

    const border = Rect.all(1);
    dvui.ButtonWidget.defaults.border = border;
    dvui.DropdownWidget.defaults.border = border;
    dvui.ScrollAreaWidget.defaults.border = border;

    dvui.ScrollAreaWidget.defaults.margin = .all(5);
}
