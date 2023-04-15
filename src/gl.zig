const builtin = @import("builtin");
const std = @import("std");
const log = std.log.scoped(.gl);
const C = @import("c.zig");

fn const_array_type(comptime base: type) type {
    return []const base;
}

pub const BufferType = enum(c_uint) {
    ArrayBuffer = C.GL_ARRAY_BUFFER,
    ElementArrayBuffer = C.GL_ELEMENT_ARRAY_BUFFER,
};
pub const BufferUsage = enum(c_uint) {
    StreamDraw = C.GL_STREAM_DRAW,
    StaticDraw = C.GL_STATIC_DRAW,
    DynamicDraw = C.GL_DYNAMIC_DRAW,
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

pub const BO = @import("gl/BO.zig");
pub const Program = @import("gl/Program.zig");
pub const Sampler2D = @import("gl/Sampler2D.zig");
pub const Shader = @import("gl/Shader.zig");
pub const Texture2D = @import("gl/Texture2D.zig");

pub fn _TestError() !void {
    switch (C.glGetError()) {
        0 => {},
        // OpenGL ES 2.0-defined errors
        C.GL_INVALID_ENUM => return error.GLInvalidEnum,
        C.GL_INVALID_VALUE => return error.GLInvalidValue,
        C.GL_INVALID_OPERATION => return error.GLInvalidOperation,
        C.GL_OUT_OF_MEMORY => return error.GLOutOfMemory,
        else => |e| {
            if (comptime builtin.target.isWasm()) switch (e) {
                C.GL_CONTEXT_LOST_WEBGL => return error.GLContextLostWebGL,
                else => {},
            } else switch (e) {
                C.GL_INVALID_FRAMEBUFFER_OPERATION => return error.GLInvalidFramebufferOperation,
                else => {},
            }
            log.err("OpenGL error code {x}/{}", .{ e, e });
            return error.GLMiscError;
        },
    }
}

pub fn bindBuffer(buffer_type: BufferType, bo: BO) !void {
    if (bo.handle == 0) return error.DummyNotAllocated;
    C.glBindBuffer(@enumToInt(buffer_type), bo.handle);
    try _TestError();
}

pub fn unbindBuffer(buffer_type: BufferType) !void {
    C.glBindBuffer(@enumToInt(buffer_type), 0);
    try _TestError();
}

pub fn bufferData(buffer_type: BufferType, comptime data_type: type, data: const_array_type(data_type), usage: BufferUsage) !void {
    C.glBufferData(
        @enumToInt(buffer_type),
        @intCast(c_long, @sizeOf(data_type) * data.len),
        &data[0],
        @enumToInt(usage),
    );
    try _TestError();
}

pub fn useProgram(program: Program) !void {
    if (program.handle == 0) return error.DummyNotAllocated;
    C.glUseProgram(program.handle);
    try _TestError();
}

pub fn unuseProgram() !void {
    C.glUseProgram(0);
    try _TestError();
}

pub fn activeTexture(idx: usize) !void {
    C.glActiveTexture(@intCast(C.GLenum, C.GL_TEXTURE0) + @intCast(C.GLenum, idx));
    try _TestError();
}

pub fn vertexAttribPointer(idx: C.GLuint, comptime ptr_type: type, comptime field_name: []const u8) !void {
    const field_type = @TypeOf(@field(@intToPtr(*allowzero ptr_type, 0), field_name));
    const base_field_type = switch (@typeInfo(field_type)) {
        .Array => |ti| ti.child,
        else => field_type,
    };

    C.glVertexAttribPointer(
        idx,
        switch (@typeInfo(field_type)) {
            .Array => |ti| switch (ti.len) {
                1, 2, 3, 4 => |v| v,
                else => @compileError("unhandled length for " ++ field_name),
            },
            else => 1,
        },
        switch (base_field_type) {
            u8 => C.GL_UNSIGNED_BYTE,
            u16 => C.GL_UNSIGNED_SHORT,
            i8 => C.GL_BYTE,
            i16 => C.GL_SHORT,
            f32 => C.GL_FLOAT,
            else => @compileError("unhandled element type for " ++ field_name),
        },
        switch (base_field_type) {
            u8, u16, i8, i16 => C.GL_TRUE,
            f32 => C.GL_FALSE,
            else => @compileError("unhandled normalisation for " ++ field_name),
        },
        @sizeOf(ptr_type),
        if (comptime builtin.target.isWasm())
            @intCast(C.GLintptr, @offsetOf(ptr_type, field_name))
        else
            &(@field(@intToPtr(*allowzero ptr_type, 0), field_name)),
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

pub fn drawArrays(mode: DrawMode, first: usize, count: usize) !void {
    C.glDrawArrays(
        @enumToInt(mode),
        @intCast(C.GLint, first),
        @intCast(C.GLsizei, count),
    );
    try _TestError();
}

pub fn drawElements(mode: DrawMode, first: usize, count: usize, comptime elem_type: type) !void {
    C.glDrawElements(
        @enumToInt(mode),
        @intCast(C.GLsizei, count),
        switch (elem_type) {
            u8 => C.GL_UNSIGNED_BYTE,
            u16 => C.GL_UNSIGNED_SHORT,
            else => @compileError("unhandled element index type"),
        },
        if (comptime builtin.target.isWasm())
            @intCast(C.GLintptr, first * @sizeOf(elem_type))
        else
            @intToPtr(*allowzero anyopaque, first * @sizeOf(elem_type)),
    );
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

pub const EnableTypes = enum(C.GLenum) {
    Blend = C.GL_BLEND,
    CullFace = C.GL_CULL_FACE,
    DepthTest = C.GL_DEPTH_TEST,
    Dither = C.GL_DITHER,
    PolygonOffsetFill = C.GL_POLYGON_OFFSET_FILL,
    SampleAlphaToCoverage = C.GL_SAMPLE_ALPHA_TO_COVERAGE,
    SampleCoverage = C.GL_SAMPLE_COVERAGE,
    ScissorTest = C.GL_SCISSOR_TEST,
    StencilTest = C.GL_STENCIL_TEST,
};
pub fn enable(t: EnableTypes) !void {
    C.glEnable(@enumToInt(t));
    try _TestError();
}
pub fn disable(t: EnableTypes) !void {
    C.glDisable(@enumToInt(t));
    try _TestError();
}
pub fn isEnabled(t: EnableTypes) !bool {
    const result = if (comptime builtin.target.isWasm())
        C.glIsEnabled(@enumToInt(t))
    else switch (C.glIsEnabled(@enumToInt(t))) {
        C.GL_FALSE => false,
        C.GL_TRUE => true,
        else => @panic("driver broke and returned invalid boolean for glIsEnabled"),
    };
    try _TestError();
    return result;
}

pub fn setEnabled(t: EnableTypes, state: bool) !void {
    if (state) {
        try enable(t);
    } else {
        try disable(t);
    }
}
