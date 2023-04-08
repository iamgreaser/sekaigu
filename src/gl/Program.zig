const builtin = @import("builtin");
const std = @import("std");
const log = std.log.scoped(.gl_Program);
const C = @import("../c.zig");
const gl = @import("../gl.zig");
const _TestError = gl._TestError;
const linalg = @import("../linalg.zig");
const Vec2f = linalg.Vec2f;
const Vec3f = linalg.Vec3f;
const Vec4f = linalg.Vec4f;
const Mat2f = linalg.Mat2f;
const Mat3f = linalg.Mat3f;
const Mat4f = linalg.Mat4f;

handle: C.GLuint,
const Self = @This();
pub const Dummy = Self{ .handle = 0 };

pub fn createProgram() !Self {
    const result = C.glCreateProgram();
    try _TestError();
    return Self{ .handle = result };
}

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
    if (comptime builtin.target.isWasm()) {
        var buf = C.glGetProgramInfoLog(self.handle);
        log.info("PROGRAM LOG: <<<\n{s}\n>>>", .{buf});
    } else {
        var buf: [1024]u8 = undefined;
        var buflen: C.GLsizei = 0;
        C.glGetProgramInfoLog(self.handle, buf.len, &buflen, &buf);
        log.info("PROGRAM LOG: <<<\n{s}\n>>>", .{buf[0..@intCast(usize, buflen)]});
    }
    try _TestError();
}

pub fn uniform(self: Self, name: []const u8, comptime T: type, value: T) !void {
    const idx = C.glGetUniformLocation(self.handle, &name[0]);
    try _TestError();
    if (idx >= 0) {
        switch (T) {
            u8, i8, u16, i16, u32, i32 => C.glUniform1i(idx, value),
            f32 => C.glUniform1f(idx, value),
            Vec2f => C.glUniform2fv(idx, 1, &value.a[0]),
            Vec3f => C.glUniform3fv(idx, 1, &value.a[0]),
            Vec4f => C.glUniform4fv(idx, 1, &value.a[0]),
            // ES2 spec v2.0.25:
            // > If the `transpose` parameter to any of the UniformMatrix* commands
            // > is not `FALSE`, an `INVALID_VALUE` error is generated,
            // > and no uniform values are changed.
            Mat2f => C.glUniformMatrix2fv(idx, 1, C.GL_FALSE, &value.a[0]),
            Mat3f => C.glUniformMatrix3fv(idx, 1, C.GL_FALSE, &value.a[0]),
            Mat4f => C.glUniformMatrix4fv(idx, 1, C.GL_FALSE, &value.a[0]),
            gl.Sampler2D => {
                // FIXME clobbers GL_ACTIVE_TEXTURE state --GM
                try gl.activeTexture(value.index);
                if (value.texture.handle == 0) {
                    try gl.Texture2D.unbindTexture();
                } else {
                    try gl.Texture2D.bindTexture(value.texture);
                }
                C.glUniform1i(idx, @intCast(C.GLint, value.index));
            },
            else => switch (@typeInfo(T)) {
                .Array => |ti| switch (ti.child) {
                    f32 => switch (ti.len) {
                        2 => C.glUniform2fv(idx, 1, &value[0]),
                        3 => C.glUniform3fv(idx, 1, &value[0]),
                        4 => C.glUniform4fv(idx, 1, &value[0]),
                        else => @compileError("unhandled uniform float array type"),
                    },
                    u8, i8, u16, i16, u32, i32 => switch (ti.len) {
                        2 => C.glUniform2iv(idx, 1, &value[0]),
                        3 => C.glUniform3iv(idx, 1, &value[0]),
                        4 => C.glUniform4iv(idx, 1, &value[0]),
                        else => @compileError("unhandled uniform int array type"),
                    },
                    else => @compileError("unhandled uniform array type"),
                },
                else => @compileError("unhandled uniform type"),
            },
        }
        try _TestError();
    }
}
