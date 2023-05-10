// SPDX-License-Identifier: AGPL-3.0-or-later
const std = @import("std");
const log = std.log.scoped(.gfx_context);
const C = @import("../c.zig");
const gl = @import("../gl.zig");

const mem = std.mem;

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
fbconfiglist_len: c_int = 0,
fbconfiglist: ?[*]C.GLXFBConfig = null,
glx_window: ?C.GLXWindow = null,
glx_context: C.GLXContext = null,

atoms: struct {
    UTF8_STRING: C.Atom,
    WM_DELETE_WINDOW: C.Atom,
    WM_PROTOCOLS: C.Atom,
    _NET_WM_ICON_NAME: C.Atom,
    _NET_WM_NAME: C.Atom,
} = undefined,

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
pub extern fn glXDestroyWindow(dpy: *C.Display, ctx: C.GLXWindow) callconv(.C) void;

pub extern fn glXMakeContextCurrent(
    dpy: *C.Display,
    draw: C.GLXDrawable,
    read: C.GLXDrawable,
    ctx: C.GLXContext,
) callconv(.C) C.Bool;
pub extern fn glXDestroyContext(dpy: *C.Display, ctx: C.GLXContext) callconv(.C) void;

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

    log.info("Fetching X11 atoms", .{});
    inline for (@typeInfo(@TypeOf(self.atoms)).Struct.fields) |field| {
        comptime var name = field.name ++ "\x00";
        @field(self.atoms, field.name) = try notNull(C.Atom, C.XInternAtom(
            self.x11_display.?,
            name,
            C.True,
        ));
    }

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
    self.fbconfiglist = try notNull(?[*]C.GLXFBConfig, glXChooseFBConfig(
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
        &self.fbconfiglist_len,
    ));
    log.debug("GLXFBContext count: {d}", .{self.fbconfiglist_len});

    log.info("Creating GLX window state", .{});
    self.glx_window = try notNull(C.GLXWindow, glXCreateWindow(
        self.x11_display.?,
        self.fbconfiglist.?[0],
        self.x11_window.?,
        &[_:0]c_int{},
    ));

    log.info("Creating GL context", .{});
    self.glx_context = try notNull(C.GLXContext, glXCreateContextAttribsARB(
        self.x11_display.?,
        self.fbconfiglist.?[0],
        null,
        C.True,
        &[_:0]c_int{
            GLX_CONTEXT_PROFILE_MASK_ARB,
            GLX_CONTEXT_ES_PROFILE_BIT_EXT,
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

    log.info("Setting window properties", .{});
    var wm_protocols = [_]C.Atom{
        self.atoms.WM_DELETE_WINDOW,
    };
    _ = try notNull(C.Status, C.XSetWMProtocols(
        self.x11_display.?,
        self.x11_window.?,
        &wm_protocols,
        wm_protocols[0..].len,
    ));
    try self.setTitle("sekaigu pre-alpha");

    log.info("Selecting inputs for window", .{});
    _ = C.XSelectInput(
        self.x11_display.?,
        self.x11_window.?,
        C.KeyPressMask | C.KeyReleaseMask | C.StructureNotifyMask,
    );

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
    if (self.glx_context) |p| {
        log.info("Disposing of GLX context", .{});
        _ = glXMakeContextCurrent(
            self.x11_display.?,
            C.None,
            C.None,
            p,
        );
        glXDestroyContext(self.x11_display.?, p);
        self.glx_context = null;
    }

    if (self.glx_window) |p| {
        log.info("Disposing of GLX window", .{});
        glXDestroyWindow(self.x11_display.?, p);
        self.glx_window = null;
    }

    if (self.fbconfiglist) |p| {
        log.info("Disposing of GLXFBConfig list", .{});
        _ = C.XFree(@ptrCast(?*anyopaque, p)); // Apparently, *?*thing is not ?*anyopaque. So the cast is needed.
        self.fbconfiglist = null;
        self.fbconfiglist_len = 0;
    }

    if (self.x11_window) |p| {
        log.info("Disposing of window", .{});
        _ = C.XDestroyWindow(self.x11_display.?, p);
        self.x11_window = null;
    }

    if (self.x11_display) |p| {
        log.info("Shutting down X11 connection", .{});
        _ = C.XCloseDisplay(p);
        self.x11_display = null;
    }

    self.* = undefined;
}

pub fn setTitle(self: *Self, title: [:0]const u8) !void {
    C.XSetTextProperty(self.x11_display.?, self.x11_window.?, &C.XTextProperty{
        .value = @constCast(title),
        .encoding = self.atoms.UTF8_STRING,
        .format = 8,
        .nitems = @intCast(c_ulong, mem.indexOfSentinel(u8, 0, title)),
    }, self.atoms._NET_WM_NAME);
}

pub fn flip(self: *Self) !void {
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
    const evcount: usize = @intCast(usize, C.XEventsQueued(self.x11_display.?, C.QueuedAfterFlush));
    for (0..evcount) |_| {
        var ev: C.XEvent = undefined;
        _ = C.XNextEvent(self.x11_display.?, &ev);
        switch (ev.type) {
            C.KeyPress, C.KeyRelease => {
                const state = (ev.type == C.KeyPress);
                // TODO: Set up XIM and XIC contexts so we can parse text (and support IMEs!) --GM
                const keysym = C.XLookupKeysym(&ev.xkey, 0);
                // TODO: Handle keysym == NoSymbol (also required for IMEs!) --GM

                log.debug("XEv Key {X:0>8} {s} {X:0>8}", .{
                    ev.xkey.window,
                    if (state) "1" else "0",
                    keysym,
                });

                noPress: {
                    (switch (keysym) {
                        C.XK_w => &keys.w,
                        C.XK_a => &keys.a,
                        C.XK_s => &keys.s,
                        C.XK_d => &keys.d,
                        C.XK_c => &keys.c,
                        C.XK_space => &keys.SPACE,
                        C.XK_Left => &keys.LEFT,
                        C.XK_Right => &keys.RIGHT,
                        C.XK_Up => &keys.UP,
                        C.XK_Down => &keys.DOWN,
                        else => break :noPress,
                    }).* = state;
                }
            },

            C.ConfigureNotify => {
                const cn = &ev.xconfigure;
                log.debug("XEv ConfigureNotify {X:0>8} {d} {d}", .{ cn.window, cn.width, cn.height });
                if (cn.window == self.x11_window.?) {
                    try self.handleResize(cn.width, cn.height);
                }
            },

            C.ClientMessage => {
                log.debug("XEv Client {any}", .{ev.xclient});
                if (ev.xclient.data.l[0] == self.atoms.WM_DELETE_WINDOW) {
                    log.info("WM_DELETE_WINDOW received, shutting down", .{});
                    return true;
                }
            },

            else => {
                log.debug("XEv {any} {any}", .{ ev.type, ev });
            },
        }
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
