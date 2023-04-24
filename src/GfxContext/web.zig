const std = @import("std");
const log = std.log.scoped(.gfx_context);
const C = @import("../c.zig");
const gl = @import("../gl.zig");

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

pub fn setTitle(self: *Self, title: [:0]const u8) !void {
    // TODO! --GM
    _ = self;
    _ = title;
}

pub fn free(self: *Self) void {
    //
    log.info("Deinitialising web context", .{});
    _ = self;
}

pub fn flip(self: *Self) !void {
    // Handled as part of the JS event loop.
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

    var buf: [1024]u8 = undefined;
    while (true) {
        const evlen = C.fetch_event(&buf, buf.len);
        if (evlen == 0) {
            return false;
        }
        const evstr = buf[0..evlen];
        switch (evstr[0]) {
            'K', 'k' => {
                // K: Key down
                // k: Key up
                const pressed = (evstr[0] == 'K');
                const code = evstr[1..];
                gotkey: inline for (@typeInfo(@TypeOf(keys.*)).Struct.fields) |field| {
                    if (std.mem.eql(u8, code, field.name)) {
                        @field(keys, field.name) = pressed;
                        break :gotkey;
                    }
                }
            },
            else => {
                log.err("Unhandled event type <{s}> for event <{s}>", .{ evstr[0..1], evstr });
            },
        }
    }
}
