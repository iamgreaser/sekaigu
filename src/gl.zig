const std = @import("std");
const log = std.log.scoped(.gl);
const C = @import("c.zig");

pub const ShaderType = enum(c_uint) {
    Vertex = C.GL_VERTEX_SHADER,
    Fragment = C.GL_FRAGMENT_SHADER,
};

pub const Shader = struct {
    handle: C.GLuint,
    const Self = @This();
    pub const Dummy = Self{ .handle = 0 };

    pub fn shaderSource(shader: Shader, src: []const u8) !void {
        C.glShaderSource(
            shader.handle,
            1,
            &[_][*c]const u8{&src[0]},
            &[_]C.GLint{@intCast(c_int, src.len)},
        );
        try _TestError();
    }

    pub fn compileShader(self: Self) !void {
        C.glCompileShader(self.handle);
        {
            var buf: [1024]u8 = undefined;
            var buflen: C.GLsizei = 0;
            C.glGetShaderInfoLog(self.handle, buf.len, &buflen, &buf);
            log.info("SHADER LOG: <<<\n{s}\n>>>", .{buf[0..@intCast(usize, buflen)]});
        }
        try _TestError();
    }
};

pub const Program = struct {
    handle: C.GLuint,
    const Self = @This();
    pub const Dummy = Self{ .handle = 0 };

    pub fn attachShader(self: Self, shader: Shader) !void {
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
};

pub fn _TestError() !void {
    switch (C.glGetError()) {
        0 => {},
        C.GL_INVALID_VALUE => return error.GLInvalidValue,
        C.GL_INVALID_OPERATION => return error.GLInvalidOperation,
        else => |e| {
            log.err("OpenGL error code {x}/{}", .{ e, e });
            return error.GLMiscError;
        },
    }
}

pub fn createProgram() !Program {
    const result = C.glCreateProgram();
    try _TestError();
    return Program{ .handle = result };
}

pub fn useProgram(program: ?Program) !void {
    if (program) |p| {
        if (p.handle == 0) return error.DummyNotAllocated;
        C.glUseProgram(p.handle);
    } else {
        C.glUseProgram(0);
    }
    try _TestError();
}

pub fn createShader(shader_type: ShaderType) !Shader {
    const result = C.glCreateShader(@enumToInt(shader_type));
    try _TestError();
    return Shader{ .handle = result };
}
