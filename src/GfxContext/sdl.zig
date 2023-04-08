const std = @import("std");
const log = std.log.scoped(.gfx_context);
const C = @import("../c.zig");

const Self = @This();

// fields
window: ?*C.SDL_Window = null,
gl_context: C.SDL_GLContext = null,
width: u16 = 800,
height: u16 = 600,

// methods
pub fn new() anyerror!Self {
    return Self{};
}

fn zeroOrNegSDLError(result: c_int) !void {
    switch (result) {
        0 => {},
        else => {
            log.err("SDL error code {}", .{-result});
            return error.SDLError;
        },
    }
}

pub fn init(self: *Self) anyerror!void {
    // Initialise SDL
    errdefer self.free();
    log.info("Initialising SDL", .{});
    switch (C.SDL_Init(C.SDL_INIT_VIDEO | C.SDL_INIT_TIMER | C.SDL_INIT_EVENTS)) {
        0 => {},
        else => {
            return error.SDLFailed;
        },
    }

    // Set up OpenGL attributes
    try zeroOrNegSDLError(C.SDL_GL_SetAttribute(C.SDL_GL_RED_SIZE, 8));
    try zeroOrNegSDLError(C.SDL_GL_SetAttribute(C.SDL_GL_GREEN_SIZE, 8));
    try zeroOrNegSDLError(C.SDL_GL_SetAttribute(C.SDL_GL_BLUE_SIZE, 8));
    try zeroOrNegSDLError(C.SDL_GL_SetAttribute(C.SDL_GL_ALPHA_SIZE, 8));
    try zeroOrNegSDLError(C.SDL_GL_SetAttribute(C.SDL_GL_DEPTH_SIZE, 24));
    try zeroOrNegSDLError(C.SDL_GL_SetAttribute(C.SDL_GL_STENCIL_SIZE, 0));

    try zeroOrNegSDLError(C.SDL_GL_SetAttribute(C.SDL_GL_CONTEXT_PROFILE_MASK, C.SDL_GL_CONTEXT_PROFILE_ES));
    try zeroOrNegSDLError(C.SDL_GL_SetAttribute(C.SDL_GL_CONTEXT_MAJOR_VERSION, 2));
    try zeroOrNegSDLError(C.SDL_GL_SetAttribute(C.SDL_GL_CONTEXT_MINOR_VERSION, 0));

    // Create a window
    log.info("Setting up a window", .{});
    if (C.SDL_CreateWindow(
        "cockel pre-alpha",
        C.SDL_WINDOWPOS_UNDEFINED,
        C.SDL_WINDOWPOS_UNDEFINED,
        self.width,
        self.height,
        C.SDL_WINDOW_OPENGL,
    )) |w| {
        self.window = w;
    } else {
        return error.WindowFailed;
    }

    // Create a GL context
    log.info("Setting up an OpenGL context", .{});
    if (C.SDL_GL_CreateContext(self.window)) |c| {
        self.gl_context = c;
    } else {
        return error.GLFailed;
    }

    // Clean up any latent OpenGL error
    _ = C.glGetError();
}

pub fn setTitle(self: *Self, title: [:0]const u8) void {
    C.SDL_SetWindowTitle(self.window, title);
}

pub fn free(self: *Self) void {
    //
    if (self.gl_context) |g| {
        log.info("Deallocating OpenGL context", .{});
        C.SDL_GL_DeleteContext(g);
        self.gl_context = null;
    }
    if (self.window) |w| {
        log.info("Deallocating window", .{});
        C.SDL_DestroyWindow(w);
        self.window = null;
    }
    log.info("Shutting down SDL", .{});
    C.SDL_Quit();
}

pub fn flip(self: *Self) void {
    if (self.window) |w| {
        C.SDL_GL_SwapWindow(w);
    } else {
        @panic("window is null!");
    }
}

pub fn applyEvents(self: Self, comptime TKeys: type, keys: *TKeys) anyerror!bool {
    _ = self;
    var ev: C.SDL_Event = undefined;
    while (C.SDL_PollEvent(&ev) != 0) {
        switch (ev.type) {
            C.SDL_QUIT => {
                return true;
            },
            C.SDL_KEYDOWN, C.SDL_KEYUP => {
                const pressed = (ev.type == C.SDL_KEYDOWN);
                const code = ev.key.keysym.sym;
                gotkey: inline for (@typeInfo(@TypeOf(keys.*)).Struct.fields) |field| {
                    if (code == @field(C, "SDLK_" ++ field.name)) {
                        @field(keys, field.name) = pressed;
                        break :gotkey;
                    }
                }
                //log.debug("key {s} {}", .{ if (pressed) "1" else "0", ev.key.keysym.sym });

            },
            else => {},
        }
    }
    return false;
}
