const builtin = @import("builtin");
pub usingnamespace if (builtin.target.isWasm())
    @import("GfxContext/web.zig")
else
    @import("GfxContext/sdl.zig");
