const std = @import("std");
const log = std.log.scoped(.gfx_context);
const C = @import("../c.zig");
const gl = @import("../gl.zig");

const windows = std.os.windows;

const Self = @This();

// missing function prototypes - TODO get these added into Zig --GM
pub extern fn SetWindowTextW(hWnd: windows.HWND, lpString: [*:0]u16) callconv(.C) windows.BOOL;
pub extern fn wglDeleteContext(unnamedParam1: ?windows.HGLRC) callconv(.C) windows.BOOL;

// extra WGL enums
const WGL_CONTEXT_MAJOR_VERSION_ARB = 0x2091;
const WGL_CONTEXT_MINOR_VERSION_ARB = 0x2092;
const WGL_CONTEXT_LAYER_PLANE_ARB = 0x2093;
const WGL_CONTEXT_FLAGS_ARB = 0x2094;
const WGL_CONTEXT_PROFILE_MASK_ARB = 0x9126;

const WGL_CONTEXT_DEBUG_BIT_ARB = 0x0001;
const WGL_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB = 0x0002;

const WGL_CONTEXT_CORE_PROFILE_BIT_ARB = 0x00000001;
const WGL_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB = 0x00000002;

const WGL_CONTEXT_ES_PROFILE_BIT_EXT = 0x00000004;
const WGL_CONTEXT_ES2_PROFILE_BIT_EXT = 0x00000004;

const ERROR_INVALID_VERSION_ARB = 0x2095;
const ERROR_INVALID_PROFILE_ARB = 0x2096;

// variables
var base_self: ?*Self = null;
var wglCreateContextAttribsARB: ?*const fn (hDC: windows.HDC, hShareContext: ?windows.HGLRC, attribList: [*:0]const c_int) callconv(.C) ?windows.HGLRC = null;

// fields
hInstance: ?windows.HINSTANCE = null,
hWnd: ?windows.HWND = null,
hDC: ?windows.HDC = null,
gl_context: ?windows.HGLRC = null,
context_initialised: bool = false,
width: u16 = 800,
height: u16 = 600,

// methods
pub fn new() anyerror!Self {
    return Self{};
}

// TODO: Get these constants added into Zig --GM
const PFD_TYPE_RGBA = 0;

const PFD_DOUBLEBUFFER = (1 << 0);
const PFD_DRAW_TO_WINDOW = (1 << 2);
const PFD_SUPPORT_OPENGL = (1 << 5);

const PFD_MAIN_PLANE = 0;

const OUR_WNDCLASS = &[_:0]u16{ 's', 'e', 'k', 'a', 'i', 'g', 'u', '_', 'm', 'a', 'i', 'n' };

pub fn init(self: *Self) anyerror!void {
    errdefer self.free();
    base_self = self;
    errdefer base_self = null;
    log.info("Initialising Win32", .{});

    log.info("Getting hInstance", .{});
    self.hInstance = @ptrCast(?windows.HINSTANCE, windows.kernel32.GetModuleHandleW(null) orelse return error.NotFound);

    log.info("Registering window class", .{});
    const wc = windows.user32.WNDCLASSEXW{
        .style = windows.user32.CS_OWNDC,
        .lpfnWndProc = wndProc,
        .hInstance = self.hInstance.?,
        .hIcon = null,
        .hCursor = null,
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = OUR_WNDCLASS,
        .hIconSm = null,
    };
    _ = try windows.user32.registerClassExW(&wc);

    log.info("Creating window", .{});
    self.hWnd = try windows.user32.createWindowExW(
        windows.user32.WS_EX_APPWINDOW,
        wc.lpszClassName,
        &[_:0]u16{ '<', '>' },
        windows.user32.WS_OVERLAPPEDWINDOW,
        windows.user32.CW_USEDEFAULT,
        windows.user32.CW_USEDEFAULT,
        self.width,
        self.height,
        null,
        null,
        self.hInstance.?,
        null,
    );

    log.info("Setting window title", .{});
    try self.setTitle("sekaigu pre-alpha");

    log.info("Showing window", .{});
    _ = windows.user32.showWindow(self.hWnd.?, windows.user32.SW_SHOWNORMAL);

    // Pump event queue until we're initialised
    while (!self.context_initialised) {
        var msg: windows.user32.MSG = undefined;
        const status = std.os.windows.user32.GetMessageW(&msg, null, 0, 0);
        if (status <= 0) {
            // Either we got an error or a WM_QUIT. Bail out with failure.
            return error.FailedToInitialiseContext;
        }
        _ = windows.user32.TranslateMessage(&msg);
        _ = windows.user32.DispatchMessageW(&msg);
    }

    // Load extensions
    log.info("Loading OpenGL extensions", .{});
    try C.loadGlExtensions(@TypeOf(C.wglGetProcAddress), C.wglGetProcAddress);

    // Clean up any latent OpenGL error
    _ = C.glGetError();
}

pub fn free(self: *Self) void {
    log.warn("TODO: Clean stuff up! --GM", .{});
    self.* = undefined;
}

fn wndProc(hWnd: windows.HWND, uMsg: windows.UINT, wParam: windows.WPARAM, lParam: windows.LPARAM) callconv(.C) windows.LRESULT {
    var self: *Self = base_self.?;
    return self.wndProcWrapped(hWnd, uMsg, wParam, lParam) catch |err| {
        log.err("Error in wndProc: {!}", .{err});
        // TODO: Work out how to pass this down the chain --GM
        windows.user32.postQuitMessage(1);
        return 0;
    };
}

fn wndProcWrapped(self: *Self, hWnd: windows.HWND, uMsg: windows.UINT, wParam: windows.WPARAM, lParam: windows.LPARAM) !windows.LRESULT {
    switch (uMsg) {
        windows.user32.WM_CREATE => {
            const pfd = windows.gdi32.PIXELFORMATDESCRIPTOR{
                .nVersion = 1,
                .dwFlags = PFD_DOUBLEBUFFER | PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL,
                .iPixelType = PFD_TYPE_RGBA,
                .cColorBits = 32,
                .cRedBits = 0,
                .cRedShift = 0,
                .cGreenBits = 0,
                .cGreenShift = 0,
                .cBlueBits = 0,
                .cBlueShift = 0,
                .cAlphaBits = 0,
                .cAlphaShift = 0,
                .cAccumBits = 0,
                .cAccumRedBits = 0,
                .cAccumGreenBits = 0,
                .cAccumBlueBits = 0,
                .cAccumAlphaBits = 0,
                .cDepthBits = 24,
                .cStencilBits = 8,
                .cAuxBuffers = 0,
                .iLayerType = PFD_MAIN_PLANE,
                .bReserved = 0,
                .dwLayerMask = 0,
                .dwVisibleMask = 0,
                .dwDamageMask = 0,
            };

            log.info("Getting device context", .{});
            self.hDC = windows.user32.GetDC(hWnd) orelse return error.DCNotFound;

            log.info("Choosing pixel format", .{});
            const pfidx = windows.gdi32.ChoosePixelFormat(self.hDC.?, &pfd);
            if (pfidx == 0) return error.ChoosePixelFormatFailed;

            log.info("Setting pixel format", .{});
            if (!windows.gdi32.SetPixelFormat(self.hDC.?, pfidx, &pfd)) return error.SetPixelFormatFailed;

            log.info("Creating OpenGL context", .{});
            var crap_context: windows.HGLRC = windows.gdi32.wglCreateContext(self.hDC.?) orelse return error.GLContextCreationFailed;
            {
                defer _ = wglDeleteContext(crap_context);

                log.info("Making OpenGL context current", .{});
                if (!windows.gdi32.wglMakeCurrent(self.hDC.?, crap_context)) return error.GLContextUseFailed;
                defer _ = windows.gdi32.wglMakeCurrent(self.hDC.?, null);

                log.info("Fetching wglCreateContextAttribsARB", .{});
                wglCreateContextAttribsARB = @ptrCast(@TypeOf(wglCreateContextAttribsARB), C.wglGetProcAddress("wglCreateContextAttribsARB"));
                if (wglCreateContextAttribsARB == null) {
                    log.err("Could not fetch wglCreateContextAttribsARB", .{});
                    return error.NotFound;
                }

                log.info("Just kidding, disusing and deleting the OpenGL context", .{});
            }

            log.info("Creating the real OpenGL context", .{});
            // If the driver doesn't support ES 2.0 via WGL, it better support GL 4.1.
            // I am NOT going to go down the "use a proprietary EGL SDK" route.
            // I am also ABSOLUTELY NOT using ANGLE - it's too big. --GM
            self.gl_context = wglCreateContextAttribsARB.?(self.hDC.?, null, &[_:0]c_int{
                WGL_CONTEXT_PROFILE_MASK_ARB,
                WGL_CONTEXT_ES_PROFILE_BIT_EXT,
                WGL_CONTEXT_MAJOR_VERSION_ARB,
                2,
                WGL_CONTEXT_MINOR_VERSION_ARB,
                0,
            });
            if (self.gl_context == null) {
                log.warn("Could not create OpenGL ES 2.0 context; creating an OpenGL 4.1 core context as a fallback", .{});
                self.gl_context = wglCreateContextAttribsARB.?(self.hDC.?, null, &[_:0]c_int{
                    WGL_CONTEXT_PROFILE_MASK_ARB,
                    WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
                    WGL_CONTEXT_MAJOR_VERSION_ARB,
                    4,
                    WGL_CONTEXT_MINOR_VERSION_ARB,
                    1,
                });
                if (self.gl_context == null) {
                    log.warn("Could not create OpenGL 4.1 core context; creating an OpenGL 4.1 compatibility context as a fallback", .{});
                    self.gl_context = wglCreateContextAttribsARB.?(self.hDC.?, null, &[_:0]c_int{
                        WGL_CONTEXT_PROFILE_MASK_ARB,
                        WGL_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB,
                        WGL_CONTEXT_MAJOR_VERSION_ARB,
                        4,
                        WGL_CONTEXT_MINOR_VERSION_ARB,
                        1,
                    });
                    if (self.gl_context == null) {
                        log.err("Could not create an OpenGL ES 2.0-compatible context!", .{});
                        return error.GLContextCreationFailed;
                    }
                }
            }

            log.info("Making OpenGL context current", .{});
            if (!windows.gdi32.wglMakeCurrent(self.hDC.?, self.gl_context.?)) return error.GLContextUseFailed;

            self.context_initialised = true;
            return 0;
        },

        windows.user32.WM_SIZE => {
            const width = @truncate(u16, @intCast(u32, lParam));
            const height = @intCast(u16, @intCast(u32, lParam) >> 16);
            log.debug("Resize {d} x {d}", .{ width, height });
            try self.handleResize(width, height);
            return 0;
        },

        else => return windows.user32.DefWindowProcW(hWnd, uMsg, wParam, lParam),
    }
}

pub fn setTitle(self: *Self, title: [:0]const u8) !void {
    var buf: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    defer fba.reset();
    const allocator = fba.allocator();
    var widetitle = std.unicode.utf8ToUtf16LeWithNull(allocator, title) catch |err| {
        log.err("Could not generate window title string: {!}", .{err});
        return error.SetTitleFailed;
    };
    defer allocator.free(widetitle);
    if (SetWindowTextW(self.hWnd.?, widetitle) == 0) {
        log.err("Could not set window title", .{});
        return error.SetTitleFailed;
    }
}

pub fn flip(self: *Self) !void {
    if (!windows.gdi32.SwapBuffers(self.hDC.?)) return error.BufferFlipFailed;
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
