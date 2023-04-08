const std = @import("std");
const log = std.log.scoped(.gfx_context);
const C = @import("../c.zig");

const Self = @This();

// fields
width: u16 = 800,
height: u16 = 600,

// methods
pub fn new() anyerror!Self {
    return Self{};
}

pub fn init(self: *Self) anyerror!void {
    // Initialise WebGL
    errdefer self.free();
    log.info("Initialising web context", .{});

    // Set up OpenGL attributes
    //try zeroOrNegSDLError(C.SDL_GL_SetAttribute(C.SDL_GL_RED_SIZE, 8));
    //try zeroOrNegSDLError(C.SDL_GL_SetAttribute(C.SDL_GL_GREEN_SIZE, 8));
    //try zeroOrNegSDLError(C.SDL_GL_SetAttribute(C.SDL_GL_BLUE_SIZE, 8));
    //try zeroOrNegSDLError(C.SDL_GL_SetAttribute(C.SDL_GL_ALPHA_SIZE, 8));
    //try zeroOrNegSDLError(C.SDL_GL_SetAttribute(C.SDL_GL_DEPTH_SIZE, 24));
    //try zeroOrNegSDLError(C.SDL_GL_SetAttribute(C.SDL_GL_STENCIL_SIZE, 0));
    //try zeroOrNegSDLError(C.SDL_GL_SetAttribute(C.SDL_GL_CONTEXT_PROFILE_MASK, C.SDL_GL_CONTEXT_PROFILE_ES));
    //try zeroOrNegSDLError(C.SDL_GL_SetAttribute(C.SDL_GL_CONTEXT_MAJOR_VERSION, 2));
    //try zeroOrNegSDLError(C.SDL_GL_SetAttribute(C.SDL_GL_CONTEXT_MINOR_VERSION, 0));

    // Clean up any latent OpenGL error
    _ = C.glGetError();
}

pub fn setTitle(self: *Self, title: [:0]const u8) void {
    // TODO! --GM
    _ = self;
    _ = title;
}

pub fn free(self: *Self) void {
    //
    log.info("Deinitialising web context", .{});
    _ = self;
}

pub fn flip(self: *Self) void {
    // TODO! --GM
    _ = self;
}

pub fn applyEvents(self: Self, comptime TKeys: type, keys: *TKeys) anyerror!bool {
    // TODO! --GM
    _ = self;
    _ = keys;
    return false;
}
