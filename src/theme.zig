const std = @import("std");
const dvui = @import("dvui");

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
    theme.control.fill = theme.control.fill;
    break :blk theme;
};

pub const dark = blk: {
    var theme = dvui.Theme.builtin.adwaita_dark;
    // TODO: customize here
    theme.control.fill = theme.control.fill;
    break :blk theme;
};
