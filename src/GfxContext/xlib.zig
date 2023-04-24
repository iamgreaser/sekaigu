const std = @import("std");
const log = std.log.scoped(.gfx_context);
const C = @import("../c.zig");
const gl = @import("../gl.zig");

const Self = @This();

// from GLX 1.4
const GLX_USE_GL = 1;
const GLX_BUFFER_SIZE = 2;
const GLX_LEVEL = 3;
const GLX_RGBA = 4;
const GLX_DOUBLEBUFFER = 5;
const GLX_STEREO = 6;
const GLX_AUX_BUFFERS = 7;
const GLX_RED_SIZE = 8;
const GLX_GREEN_SIZE = 9;
const GLX_BLUE_SIZE = 10;
const GLX_ALPHA_SIZE = 11;
const GLX_DEPTH_SIZE = 12;
const GLX_STENCIL_SIZE = 13;
const GLX_ACCUM_RED_SIZE = 14;
const GLX_ACCUM_GREEN_SIZE = 15;
const GLX_ACCUM_BLUE_SIZE = 16;
const GLX_ACCUM_ALPHA_SIZE = 17;
const GLX_CONFIG_CAVEAT = 0x20;
const GLX_VISUAL_CAVEAT_EXT = 0x20;
const GLX_X_VISUAL_TYPE = 0x22;
const GLX_X_VISUAL_TYPE_EXT = 0x22;
const GLX_TRANSPARENT_TYPE = 0x23;
const GLX_TRANSPARENT_TYPE_EXT = 0x23;
const GLX_TRANSPARENT_INDEX_VALUE = 0x24;
const GLX_TRANSPARENT_INDEX_VALUE_EXT = 0x24;
const GLX_TRANSPARENT_RED_VALUE = 0x25;
const GLX_TRANSPARENT_RED_VALUE_EXT = 0x25;
const GLX_TRANSPARENT_GREEN_VALUE = 0x26;
const GLX_TRANSPARENT_GREEN_VALUE_EXT = 0x26;
const GLX_TRANSPARENT_BLUE_VALUE = 0x27;
const GLX_TRANSPARENT_BLUE_VALUE_EXT = 0x27;
const GLX_TRANSPARENT_ALPHA_VALUE = 0x28;
const GLX_TRANSPARENT_ALPHA_VALUE_EXT = 0x28;

// from GLX_ARB_create_context
const GLX_CONTEXT_MAJOR_VERSION_ARB = 0x2091;
const GLX_CONTEXT_MINOR_VERSION_ARB = 0x2092;
const GLX_CONTEXT_FLAGS_ARB = 0x2094;
const GLX_CONTEXT_PROFILE_MASK_ARB = 0x9126;
const GLX_CONTEXT_DEBUG_BIT_ARB = 0x0001;
const GLX_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB = 0x0002;
const GLX_CONTEXT_CORE_PROFILE_BIT_ARB = 0x00000001;
const GLX_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB = 0x00000002;

// from GLX_EXT_create_context_es2_profile
const GLX_CONTEXT_ES_PROFILE_BIT_EXT = 0x00000004;
const GLX_CONTEXT_ES2_PROFILE_BIT_EXT = 0x00000004;

// fields
//window: ?*C.SDL_Window = null,
//gl_context: C.SDL_GLContext = null,
width: u16 = 800,
height: u16 = 600,
x11_display: ?*C.Display = null,
x11_window: ?C.Window = null,
glx_context: C.GLXContext = null,
glx_window: ?C.GLXWindow = null,

pub extern fn glXChooseFBConfig(
    dpy: *C.Display,
    screen: c_int,
    attrib_list: [*:0]const c_int,
    nelements: *c_int,
) callconv(.C) ?[*]C.GLXFBConfig;

pub extern fn glXCreateWindow(
    dpy: *C.Display,
    config: C.GLXFBConfig,
    win: C.Window,
    attrib_list: [*:0]const c_int,
) callconv(.C) C.GLXWindow;

pub extern fn glXMakeContextCurrent(
    dpy: *C.Display,
    draw: C.GLXDrawable,
    read: C.GLXDrawable,
    ctx: C.GLXContext,
) callconv(.C) C.Bool;

pub extern fn glXWaitGL() callconv(.C) void;
pub extern fn glXWaitX() callconv(.C) void;
pub extern fn glXSwapBuffers(dpy: *C.Display, draw: C.GLXDrawable) callconv(.C) void;

var _ptr_glXCreateContextAttribsARB: ?*const fn (
    dpy: *C.Display,
    config: C.GLXFBConfig,
    share_context: C.GLXContext,
    direct: C.Bool,
    attrib_list: [*:0]const c_int,
) callconv(.C) C.GLXContext = null;
pub fn glXCreateContextAttribsARB(
    dpy: *C.Display,
    config: C.GLXFBConfig,
    share_context: C.GLXContext,
    direct: C.Bool,
    attrib_list: [*:0]const c_int,
) callconv(.C) C.GLXContext {
    if (_ptr_glXCreateContextAttribsARB == null) {
        _ptr_glXCreateContextAttribsARB = @ptrCast(@TypeOf(_ptr_glXCreateContextAttribsARB), C.glXGetProcAddress("glXCreateContextAttribsARB"));
        if (_ptr_glXCreateContextAttribsARB == null) {
            log.err("Could not load pointer to glXCreateContextAttribsARB", .{});
            return null;
        }
    }
    return _ptr_glXCreateContextAttribsARB.?(dpy, config, share_context, direct, attrib_list);
}

// methods
pub fn new() anyerror!Self {
    return Self{};
}

pub fn init(self: *Self) anyerror!void {
    // Initialise X11
    errdefer self.free();
    log.info("Initialising Xlib", .{});
    self.x11_display = try notNull(?*C.Display, C.XOpenDisplay(null));

    log.info("Creating window", .{});
    const root_window = try notNull(C.Window, C.XDefaultRootWindow(self.x11_display.?));
    var window_attrs: C.XSetWindowAttributes = undefined;
    self.x11_window = try notNull(C.Window, C.XCreateWindow(
        self.x11_display.?,
        root_window,
        0,
        0,
        self.width,
        self.height,
        0,
        24,
        C.InputOutput,
        @intToPtr(*allowzero C.Visual, C.CopyFromParent),
        0,
        &window_attrs,
    ));

    log.info("Fetching appropriate GLXFBContext", .{});
    var fbconfiglist_len: c_int = 0;
    var fbconfiglist: [*]C.GLXFBConfig = try notNull(?[*]C.GLXFBConfig, glXChooseFBConfig(
        self.x11_display.?,
        C.XScreenNumberOfScreen(C.XDefaultScreenOfDisplay(self.x11_display.?)),
        &[_:0]c_int{
            GLX_RED_SIZE,     1,
            GLX_GREEN_SIZE,   1,
            GLX_BLUE_SIZE,    1,
            GLX_ALPHA_SIZE,   1,
            GLX_DEPTH_SIZE,   16,
            GLX_STENCIL_SIZE, 8,
            GLX_DOUBLEBUFFER, C.True,
        },
        &fbconfiglist_len,
    ));
    log.debug("GLXFBContext count: {d}", .{fbconfiglist_len});
    defer _ = C.XFree(@ptrCast(?*anyopaque, fbconfiglist)); // Apparently, *?*thing is not ?*anyopaque. So the cast is needed.

    log.info("Creating GLX window state", .{});
    self.glx_window = try notNull(C.GLXWindow, glXCreateWindow(
        self.x11_display.?,
        fbconfiglist[0],
        self.x11_window.?,
        &[_:0]c_int{},
    ));

    log.info("Creating GL context", .{});
    self.glx_context = try notNull(C.GLXContext, glXCreateContextAttribsARB(
        self.x11_display.?,
        fbconfiglist[0],
        null,
        C.True,
        &[_:0]c_int{
            GLX_CONTEXT_PROFILE_MASK_ARB,
            GLX_CONTEXT_ES2_PROFILE_BIT_EXT,
            GLX_CONTEXT_MAJOR_VERSION_ARB,
            2,
            GLX_CONTEXT_MINOR_VERSION_ARB,
            0,
        },
    ));

    log.info("Making context current", .{});
    _ = glXMakeContextCurrent(
        self.x11_display.?,
        self.glx_window.?,
        self.glx_window.?,
        self.glx_context.?,
    );

    // TODO: Set window title (and icon?) --GM

    log.info("Showing window", .{});
    _ = C.XMapRaised(self.x11_display.?, self.x11_window.?);

    // Load extensions
    log.info("Loading OpenGL extensions", .{});
    try C.loadGlExtensions(@TypeOf(C.glXGetProcAddress), C.glXGetProcAddress);

    log.info("Syncing X11 stream", .{});
    _ = C.XSync(self.x11_display.?, C.False);

    // Clean up any latent OpenGL error
    _ = C.glGetError();
}

pub fn free(self: *Self) void {
    if (self.glx_window) |p| {
        log.info("Disposing of GLX window", .{});
        log.warn("TODO: Actually delete glx_window --GM", .{});
        _ = p;
        self.glx_window = null;
    }

    if (self.glx_context) |p| {
        log.info("Disposing of GLX context", .{});
        log.warn("TODO: Actually delete glx_context --GM", .{});
        _ = p;
        self.glx_context = null;
    }

    if (self.x11_window) |p| {
        log.info("Disposing of window", .{});
        log.warn("TODO: Actually delete x11_window --GM", .{});
        _ = p;
        self.x11_window = null;
    }

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
    // TODO actually work out how much of this is necessary --GM
    glXWaitGL();
    glXSwapBuffers(self.x11_display.?, self.glx_window.?);
    glXWaitX();
}

pub fn handleResize(self: *Self, width: i32, height: i32) !void {
    self.width = @intCast(u16, width);
    self.height = @intCast(u16, height);
    C.glViewport(0, 0, width, height);
    try gl._TestError();
}

pub fn applyEvents(self: *Self, comptime TKeys: type, keys: *TKeys) anyerror!bool {
    _ = keys;
    const evcount: usize = @intCast(usize, C.XEventsQueued(self.x11_display.?, C.QueuedAfterFlush));
    for (0..evcount) |_| {
        var ev: C.XEvent = undefined;
        _ = C.XNextEvent(self.x11_display.?, &ev);
        log.debug("XEv {any}", .{ev});
    }
    return false;
}

// helpers
fn notNull(comptime T: type, value: T) !switch (@typeInfo(T)) {
    .Optional => |ti| ti.child,
    .Int => T,
    else => @compileError("unhandled type"),
} {
    return switch (@typeInfo(@TypeOf(value))) {
        .Optional => value orelse error.Failed,
        .Int => if (value == 0) error.Failed else value,
        else => @compileError("unhandled type"),
    };
}
