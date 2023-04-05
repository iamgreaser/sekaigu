const std = @import("std");
const log = std.log.scoped(.gl);
const C = @import("c.zig");

pub const BufferType = enum(c_uint) {
    ArrayBuffer = C.GL_ARRAY_BUFFER,
};
pub const BufferUsage = enum(c_uint) {
    StreamDraw = C.GL_STREAM_DRAW,
    StreamRead = C.GL_STREAM_READ,
    StreamCopy = C.GL_STREAM_COPY,
    StaticDraw = C.GL_STATIC_DRAW,
    StaticRead = C.GL_STATIC_READ,
    StaticCopy = C.GL_STATIC_COPY,
    DynamicDraw = C.GL_DYNAMIC_DRAW,
    DynamicRead = C.GL_DYNAMIC_READ,
    DynamicCopy = C.GL_DYNAMIC_COPY,
};

pub const BO = struct {
    handle: C.GLuint,
    const Self = @This();
    pub const Dummy = Self{ .handle = 0 };
};

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

pub fn genBuffer() !BO {
    var result: C.GLuint = 0;
    C.glGenBuffers(1, &result);
    try _TestError();
    return BO{ .handle = result };
}

pub fn bindBuffer(buffer_type: BufferType, opt_bo: ?BO) !void {
    if (opt_bo) |bo| {
        if (bo.handle == 0) return error.DummyNotAllocated;
        C.glBindBuffer(@enumToInt(buffer_type), bo.handle);
    } else {
        C.glBindBuffer(@enumToInt(buffer_type), 0);
    }
    try _TestError();
}

pub fn bufferData(buffer_type: BufferType, size: usize, data: anytype, usage: BufferUsage) !void {
    C.glBufferData(
        @enumToInt(buffer_type),
        @intCast(c_long, size),
        data,
        @enumToInt(usage),
    );
    try _TestError();
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
