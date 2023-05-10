// SPDX-License-Identifier: AGPL-3.0-or-later
const builtin = @import("builtin");
const std = @import("std");
const log = std.log.scoped(.gl_Shader);
const C = @import("../c.zig");
const gl = @import("../gl.zig");
const _TestError = gl._TestError;

handle: C.GLuint,
const Self = @This();
pub const Dummy = Self{ .handle = 0 };

pub const Type = enum(c_uint) {
    Vertex = C.GL_VERTEX_SHADER,
    Fragment = C.GL_FRAGMENT_SHADER,
};

pub fn createShader(shader_type: Self.Type) !Self {
    const result = C.glCreateShader(@enumToInt(shader_type));
    try _TestError();
    return Self{ .handle = result };
}

pub fn shaderSource(shader: Self, src: [:0]const u8) !void {
    if (comptime builtin.target.isWasm()) {
        C.glShaderSource(shader.handle, src);
    } else {
        C.glShaderSource(
            shader.handle,
            1,
            &[_][*:0]const u8{src},
            null,
        );
    }
    try _TestError();
}

pub fn compileShader(self: Self) !void {
    C.glCompileShader(self.handle);
    if (comptime builtin.target.isWasm()) {
        const buf = C.glGetShaderInfoLog(self.handle);
        log.info("SHADER LOG: <<<\n{s}\n>>>", .{buf});
    } else {
        var buf: [1024:0]u8 = undefined;
        var buflen: C.GLsizei = 0;
        C.glGetShaderInfoLog(self.handle, buf.len, &buflen, &buf);
        log.info("SHADER LOG: <<<\n{s}\n>>>", .{buf[0..@intCast(usize, buflen)]});
    }
    try _TestError();
}
