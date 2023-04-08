const std = @import("std");
const log = std.log.scoped(.gl_Program);
const C = @import("../c.zig");
const gl = @import("../gl.zig");
const _TestError = gl._TestError;

index: C.GLuint,
texture: gl.Texture2D = gl.Texture2D.Dummy,
const Self = @This();
pub const Dummy = Self{ .handle = 0 };

pub fn makeSampler(index: C.GLuint) Self {
    return Self{
        .index = index,
    };
}

pub fn bindTexture(self: *Self, tex: gl.Texture2D) anyerror!void {
    self.texture = tex;
}
