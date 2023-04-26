const builtin = @import("builtin");
const std = @import("std");
const log = std.log.scoped(.gfx_context);
const C = @import("../c.zig");
const gl = @import("../gl.zig");

const windows = std.os.windows;

const LinearFifo = std.fifo.LinearFifo;

const Self = @This();

// helpers
const WINAPI = windows.WINAPI;

// missing function prototypes - TODO get these added into Zig --GM
extern fn SetWindowTextW(hWnd: windows.HWND, lpString: [*:0]u16) callconv(WINAPI) windows.BOOL;
extern fn wglDeleteContext(unnamedParam1: ?windows.HGLRC) callconv(WINAPI) windows.BOOL;
extern fn wglGetProcAddress(unnamedParam1: [*:0]const u8) callconv(WINAPI) ?*const fn () callconv(WINAPI) void;

// things which are older than what Zig would actually care about
const WNDCLASSW = extern struct {
    style: windows.UINT,
    lpfnWndProc: windows.user32.WNDPROC,
    cbClsExtra: i32 = 0,
    cbWndExtra: i32 = 0,
    hInstance: windows.HINSTANCE,
    hIcon: ?windows.HICON,
    hCursor: ?windows.HCURSOR,
    hbrBackground: ?windows.HBRUSH,
    lpszMenuName: ?[*:0]const u16,
    lpszClassName: [*:0]const u16,
};
pub extern "user32" fn RegisterClassW(*const WNDCLASSW) callconv(WINAPI) windows.ATOM;
pub extern "user32" fn CreateWindowExW(dwExStyle: windows.DWORD, lpClassName: [*:0]const u16, lpWindowName: [*:0]const u16, dwStyle: windows.DWORD, X: i32, Y: i32, nWidth: i32, nHeight: i32, hWindParent: ?windows.HWND, hMenu: ?windows.HMENU, hInstance: windows.HINSTANCE, lpParam: ?windows.LPVOID) callconv(WINAPI) ?windows.HWND;

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

const KeyEvent = struct { vkey: u16, state: bool };
const KeyFifoType = LinearFifo(KeyEvent, .{ .Static = 1024 });

// variables
var base_self: ?*Self = null;
var wglCreateContextAttribsARB: ?*const fn (hDC: windows.HDC, hShareContext: ?windows.HGLRC, attribList: [*:0]const c_int) callconv(.C) ?windows.HGLRC = null;

// fields
hInstance: ?windows.HINSTANCE = null,
hWnd: ?windows.HWND = null,
hDC: ?windows.HDC = null,
gl_context: ?windows.HGLRC = null,
width: u16 = 800,
height: u16 = 600,

key_fifo: KeyFifoType = KeyFifoType.init(),

// methods
pub fn new() anyerror!Self {
    return Self{};
}

// TODO: Get these constants added into Zig --GM
const VK = struct {
    pub const SPACE = 0x20;
    pub const LEFT = 0x25;
    pub const UP = 0x26;
    pub const RIGHT = 0x27;
    pub const DOWN = 0x28;
};

const PFD_TYPE_RGBA = 0;

const PFD_DOUBLEBUFFER = (1 << 0);
const PFD_DRAW_TO_WINDOW = (1 << 2);
const PFD_SUPPORT_OPENGL = (1 << 5);

const PFD_MAIN_PLANE = 0;

const OUR_WNDCLASS = &[_:0]u16{ 's', 'e', 'k', 'a', 'i', 'g', 'u', '_', 'm', 'a', 'i', 'n' };

pub fn init(self: *Self) anyerror!void {
    errdefer self.free();
    base_self = self;
    log.info("Initialising Win32", .{});

    log.info("Getting hInstance", .{});
    self.hInstance = @ptrCast(?windows.HINSTANCE, windows.kernel32.GetModuleHandleW(null) orelse return error.NotFound);

    log.info("Registering window class", .{});
    const wc = WNDCLASSW{
        .style = windows.user32.CS_OWNDC,
        .lpfnWndProc = wndProc,
        .hInstance = self.hInstance.?,
        .hIcon = null,
        .hCursor = null,
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = OUR_WNDCLASS,
    };
    if (RegisterClassW(&wc) == 0) {
        const winerr = windows.kernel32.GetLastError();
        log.err("Windows error {d}", .{winerr});
        return error.Failed;
    }

    // CreateWindow(|Ex)(W|A) sends WM_CREATE immediately.
    // That is, there's no need to run GetMessage(W|A)/TranslateMessage/DispatchMessage(W|A) ourselves.
    //
    // Our WndProc's response to the message will either be:
    // *  0: The window was created successfully.
    // * -1: Something failed, and we want CreateWindow(|Ex)(W|A) to return NULL.
    //
    log.info("Creating window", .{});
    self.hWnd = CreateWindowExW(
        0,
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
    ) orelse {
        const winerr = windows.kernel32.GetLastError();
        log.err("Windows error {d}", .{winerr});
        return error.Failed;
    };

    log.info("Setting window title", .{});
    try self.setTitle("sekaigu pre-alpha");

    log.info("Showing window", .{});
    _ = windows.user32.showWindow(self.hWnd.?, windows.user32.SW_SHOWNORMAL);

    // Load extensions
    log.info("Loading OpenGL extensions", .{});
    try C.loadGlExtensions(@TypeOf(wglGetProcAddress), wglGetProcAddress);

    // Clean up any latent OpenGL error
    _ = C.glGetError();
}

pub fn free(self: *Self) void {
    if (self.gl_context) |p| {
        if (self.hDC) |hDC| {
            if (self.hWnd != null) {
                log.info("Detaching GL context", .{});
                _ = windows.gdi32.wglMakeCurrent(hDC, null);
            }
        }
        log.info("Destroying GL context", .{});
        _ = wglDeleteContext(p);
        self.gl_context = null;
    }

    if (self.hDC) |hDC| {
        if (self.hWnd) |hWnd| {
            log.info("Destroying device context", .{});
            _ = windows.user32.ReleaseDC(hWnd, hDC);
        }
        self.hDC = null;
    }

    if (self.hWnd) |hWnd| {
        log.info("Destroying window", .{});
        windows.user32.destroyWindow(hWnd) catch |err| {
            log.err("DestroyWindow failed: {!}", .{err});
            // Squelch error anyway
        };
        self.hWnd = null;
    }

    self.hInstance = null;
    base_self = null;
    self.* = undefined;
}

fn wndProc(hWnd: windows.HWND, uMsg: windows.UINT, wParam: windows.WPARAM, lParam: windows.LPARAM) callconv(WINAPI) windows.LRESULT {
    var self: *Self = base_self.?;
    //log.debug("wndproc {X:0>16} {X:0>16} {X:0>16} {X:0>16}", .{ @ptrToInt(hWnd), uMsg, wParam, lParam });
    return self.wndProcWrapped(hWnd, uMsg, wParam, lParam) catch |err| {
        log.err("Error in wndProc: {!}", .{err});
        // TODO: Work out how to pass this down the chain --GM
        switch (uMsg) {
            // This is sent directly from CreateWindow(|Ex)(W|A).
            // If we return -1, then the window is destroyed and CreateWindow(|Ex)(W|A) returns NULL.
            windows.user32.WM_CREATE => return -1,

            else => {
                windows.user32.postQuitMessage(1);
                return 0;
            },
        }
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
            errdefer ({
                log.info("Destroying device context", .{});
                _ = windows.user32.ReleaseDC(hWnd, self.hDC.?);
                self.hDC = null;
                log.info("OK Destroying device context", .{});
            });

            log.info("Choosing pixel format", .{});
            const pfidx = windows.gdi32.ChoosePixelFormat(self.hDC.?, &pfd);
            if (pfidx == 0) return error.ChoosePixelFormatFailed;

            log.info("Setting pixel format", .{});
            if (!windows.gdi32.SetPixelFormat(self.hDC.?, pfidx, &pfd)) return error.SetPixelFormatFailed;

            log.info("Creating OpenGL context", .{});
            var crap_context: windows.HGLRC = windows.gdi32.wglCreateContext(self.hDC.?) orelse return error.GLContextCreationFailed;
            {
                defer ({
                    log.info("Destroying temporary GL context", .{});
                    _ = wglDeleteContext(crap_context);
                    log.info("OK Destroying temporary GL context", .{});
                });

                log.info("Making OpenGL context current", .{});
                if (!windows.gdi32.wglMakeCurrent(self.hDC.?, crap_context)) return error.GLContextUseFailed;
                defer ({
                    log.info("Detaching GL context", .{});
                    _ = windows.gdi32.wglMakeCurrent(self.hDC.?, null);
                    log.info("OK Detaching GL context", .{});
                });

                log.info("Fetching wglCreateContextAttribsARB", .{});
                wglCreateContextAttribsARB = @ptrCast(@TypeOf(wglCreateContextAttribsARB), wglGetProcAddress("wglCreateContextAttribsARB"));
                if (wglCreateContextAttribsARB == null) {
                    log.err("Could not fetch wglCreateContextAttribsARB", .{});
                    return error.NotFound;
                }

                log.info("Just kidding, detaching and deleting the OpenGL context", .{});
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

            return 0;
        },

        windows.user32.WM_SIZE => {
            const width = @truncate(u16, @intCast(u32, lParam));
            const height = @intCast(u16, @intCast(u32, lParam) >> 16);
            log.debug("Resize {d} x {d}", .{ width, height });
            try self.handleResize(width, height);
            return 0;
        },

        windows.user32.WM_DESTROY => {
            log.debug("destroy", .{});
            if (self.hWnd) |this_hWnd| {
                if (self.gl_context != null) {
                    if (self.hDC) |hDC| {
                        log.info("Detaching GL context", .{});
                        _ = windows.gdi32.wglMakeCurrent(hDC, null);
                    }
                }

                if (self.hDC) |hDC| {
                    log.info("Destroying device context", .{});
                    _ = windows.user32.ReleaseDC(this_hWnd, hDC);
                    self.hDC = null;
                }
                self.hWnd = null;
            }
            windows.user32.PostQuitMessage(0);
            return 0;
        },

        windows.user32.WM_KEYDOWN, windows.user32.WM_KEYUP => {
            const state = (uMsg == windows.user32.WM_KEYDOWN);
            const vkey: u16 = @intCast(u16, wParam);
            log.debug("Key W {s} {X:0>4}", .{ if (state) "1" else "0", vkey });
            try self.key_fifo.writeItem(.{ .vkey = vkey, .state = state });
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
    while (self.key_fifo.readItem()) |k| {
        log.debug("Key R {s} {X:0>4}", .{ if (k.state) "1" else "0", k.vkey });
        noPress: {
            (switch (k.vkey) {
                'W' => &keys.w,
                'A' => &keys.a,
                'S' => &keys.s,
                'D' => &keys.d,
                'C' => &keys.c,
                VK.SPACE => &keys.SPACE,
                VK.LEFT => &keys.LEFT,
                VK.RIGHT => &keys.RIGHT,
                VK.UP => &keys.UP,
                VK.DOWN => &keys.DOWN,
                else => break :noPress,
            }).* = k.state;
        }
    }
    return false;
}

// helpers
fn notNull(comptime T: type, value: ?T) !T {
    return value orelse error.Failed;
}
