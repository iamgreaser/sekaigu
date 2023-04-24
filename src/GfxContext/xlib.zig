const std = @import("std");
const log = std.log.scoped(.gfx_context);
const C = @import("../c.zig");
const gl = @import("../gl.zig");

const Self = @This();

// fields
//window: ?*C.SDL_Window = null,
//gl_context: C.SDL_GLContext = null,
width: u16 = 800,
height: u16 = 600,
x11_display: ?*C.Display = null,

// methods
pub fn new() anyerror!Self {
    return Self{};
}

pub fn init(self: *Self) anyerror!void {
    // Initialise X11
    errdefer self.free();
    log.info("Initialising Xlib", .{});
    self.x11_display = try notNull(*C.Display, C.XOpenDisplay(null));

    // Load extensions
    log.info("Loading OpenGL extensions", .{});
    try C.loadGlExtensions(@TypeOf(C.glXGetProcAddress), C.glXGetProcAddress);

    // Clean up any latent OpenGL error
    _ = C.glGetError();
}

pub fn free(self: *Self) void {
    if (self.x11_display) |p| {
        log.info("Shutting down X11 connection", .{});
        _ = C.XCloseDisplay(p);
        self.x11_display = null;
    }

    self.* = undefined;
}

pub fn setTitle(self: *Self, title: [:0]const u8) void {
    //C.SDL_SetWindowTitle(self.window, title);
    _ = self;
    _ = title;
}

pub fn flip(self: *Self) void {
    _ = self;
}

pub fn handleResize(self: *Self, width: i32, height: i32) !void {
    self.width = @intCast(u16, width);
    self.height = @intCast(u16, height);
    C.glViewport(0, 0, width, height);
    try gl._TestError();
}

pub fn applyEvents(self: *Self, comptime TKeys: type, keys: *TKeys) anyerror!bool {
    _ = self;
    _ = keys;
    return false;
}

// helpers
fn notNull(comptime T: type, value: ?T) !T {
    return value orelse error.Failed;
}
