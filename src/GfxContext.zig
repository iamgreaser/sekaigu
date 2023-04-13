pub const GfxContext = if (@import("builtin").target.isWasm())
    @import("GfxContext/web.zig")
else
    @import("GfxContext/sdl.zig");
