const std = @import("std");
const log = std.log.scoped(.gl_Program);
const C = @import("../c.zig");
const gl = @import("../gl.zig");
const _TestError = gl._TestError;

handle: C.GLuint,
const Self = @This();
pub const Dummy = Self{ .handle = 0 };

pub fn attachShader(self: Self, shader: gl.Shader) !void {
    C.glAttachShader(self.handle, shader.handle);
    try _TestError();
}

pub fn bindAttribLocation(self: Self, idx: C.GLuint, name: [:0]const u8) !void {
    C.glBindAttribLocation(self.handle, idx, name);
    try _TestError();
}

pub fn linkProgram(self: Self) !void {
    C.glLinkProgram(self.handle);
    {
        var buf: [1024]u8 = undefined;
        var buflen: C.GLsizei = 0;
        C.glGetProgramInfoLog(self.handle, buf.len, &buflen, &buf);
        log.info("PROGRAM LOG: <<<\n{s}\n>>>", .{buf[0..@intCast(usize, buflen)]});
    }
    try _TestError();
}
