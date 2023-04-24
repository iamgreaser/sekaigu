const builtin = @import("builtin");
pub const GfxContext = if (builtin.target.isWasm())
    @import("GfxContext/web.zig")
else if (builtin.target.os.tag == .windows)
    @import("GfxContext/win32.zig")
else
    @import("GfxContext/xlib.zig");
