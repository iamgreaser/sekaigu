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
pub const DrawMode = enum(c_uint) {
    Points = C.GL_POINTS,
    LineStrip = C.GL_LINE_STRIP,
    LineLoop = C.GL_LINE_LOOP,
    Lines = C.GL_LINES,
    TriangleStrip = C.GL_TRIANGLE_STRIP,
    TriangleFan = C.GL_TRIANGLE_FAN,
    Triangles = C.GL_TRIANGLES,
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

pub fn vertexAttribPointer(idx: C.GLuint, comptime ptr: anytype, comptime field_name: []const u8) !void {
    const field_type = @TypeOf(@field(ptr[0], field_name));
    C.glVertexAttribPointer(
        idx,
        switch (@typeInfo(field_type).Array.len) {
            1, 2, 3, 4 => |v| v,
            else => {
                @compileError("unhandled length for " ++ field_name);
            },
        },
        switch (@typeInfo(field_type).Array.child) {
            u8 => C.GL_UNSIGNED_BYTE,
            u16 => C.GL_UNSIGNED_SHORT,
            u32 => C.GL_UNSIGNED_INT,
            i8 => C.GL_BYTE,
            i16 => C.GL_SHORT,
            i32 => C.GL_INT,
            f32 => C.GL_FLOAT,
            f64 => C.GL_DOUBLE,
            else => {
                @compileError("unhandled element type for " ++ field_name);
            },
        },
        switch (@typeInfo(field_type).Array.child) {
            u8, u16, u32, i8, i16, i32 => C.GL_TRUE,
            f32 => C.GL_FALSE,
            else => {
                @compileError("unhandled normalisation for " ++ field_name);
            },
        },
        @sizeOf(@TypeOf(ptr[0])),
        &(@field(@intToPtr(*allowzero @TypeOf(ptr[0]), 0), field_name)),
    );
    try _TestError();
}

pub fn enableVertexAttribArray(idx: C.GLuint) !void {
    C.glEnableVertexAttribArray(idx);
    try _TestError();
}

pub fn disableVertexAttribArray(idx: C.GLuint) !void {
    C.glDisableVertexAttribArray(idx);
    try _TestError();
}

pub fn drawArrays(mode: DrawMode, first: C.GLint, count: C.GLsizei) !void {
    C.glDrawArrays(@enumToInt(mode), first, count);
    try _TestError();
}

pub fn clearColor(r: C.GLclampf, g: C.GLclampf, b: C.GLclampf, a: C.GLclampf) !void {
    C.glClearColor(r, g, b, a);
    try _TestError();
}

pub const ClearOptions = struct {
    color: bool = false,
    depth: bool = false,
    stencil: bool = false,
};
pub fn clear(clear_options: ClearOptions) !void {
    var clear_mask: C.GLbitfield = 0;
    if (clear_options.color) clear_mask |= C.GL_COLOR_BUFFER_BIT;
    if (clear_options.depth) clear_mask |= C.GL_DEPTH_BUFFER_BIT;
    if (clear_options.stencil) clear_mask |= C.GL_STENCIL_BUFFER_BIT;
    C.glClear(clear_mask);
    try _TestError();
}
