const std = @import("std");
const log = std.log.scoped(.main);
const C = @import("c.zig");

const GfxContext = @import("GfxContext.zig");
const gl = @import("gl.zig");

pub const VA_P3F_C3F = struct {
    pos: [3]f32,
    color: [3]u8,
};

const model_va = [_]VA_P3F_C3F{
    .{ .pos = .{ 0.00, 0.99, 0.00 }, .color = .{ 0xFF, 0x80, 0x80 } },
    .{ .pos = .{ -0.70, -0.50, 0.00 }, .color = .{ 0x80, 0xFF, 0x80 } },
    .{ .pos = .{ 0.70, -0.50, 0.00 }, .color = .{ 0x80, 0x80, 0xFF } },
};
var model_vbo: C.GLuint = 0;

const shader_v_src =
    \\#version 100
    \\precision highp float;
    \\
    \\attribute vec4 ipos;
    \\attribute vec4 icolor;
    \\varying vec4 vcolor;
    \\
    \\void main () {
    \\    vcolor = icolor;
    \\    gl_Position = ipos;
    \\}
;

const shader_f_src =
    \\#version 100
    \\precision highp float;
    \\
    \\varying vec4 vcolor;
    \\
    \\void main () {
    \\    gl_FragColor = vcolor;
    \\}
;
var shader_v: gl.Shader = gl.Shader.Dummy;
var shader_f: gl.Shader = gl.Shader.Dummy;
var shader_prog: gl.Program = gl.Program.Dummy;

pub fn main() !void {
    var gfx = try GfxContext.new();
    try gfx.init();
    defer gfx.free();

    log.warn("GL error status at start: {}", .{C.glGetError()});

    // Compile the shader
    shader_prog = try gl.createProgram();
    shader_v = try gl.createShader(.Vertex);
    shader_f = try gl.createShader(.Fragment);
    try shader_prog.attachShader(shader_v);
    try shader_prog.attachShader(shader_f);
    inline for (@typeInfo(@TypeOf(model_va[0])).Struct.fields, 0..) |field, i| {
        try shader_prog.bindAttribLocation(i, "i" ++ field.name);
    }
    try shader_v.shaderSource(shader_v_src);
    try shader_f.shaderSource(shader_f_src);
    try shader_v.compileShader();
    try shader_f.compileShader();
    try shader_prog.linkProgram();

    // Load the VBO
    {
        C.glGenBuffers(1, &model_vbo);
        C.glBindBuffer(C.GL_ARRAY_BUFFER, model_vbo);
        defer C.glBindBuffer(C.GL_ARRAY_BUFFER, 0);
        C.glBufferData(C.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(model_va)), &model_va, C.GL_STATIC_DRAW);
    }

    log.warn("GL error status after VBO: {}", .{C.glGetError()});

    done: while (true) {
        C.glClearColor(0.2, 0.0, 0.4, 0.0);
        C.glClear(C.GL_COLOR_BUFFER_BIT);

        {
            try gl.useProgram(shader_prog);
            defer gl.useProgram(null) catch {};
            defer {
                inline for (@typeInfo(@TypeOf(model_va[0])).Struct.fields, 0..) |_, i| {
                    C.glDisableVertexAttribArray(i);
                }
            }

            C.glBindBuffer(C.GL_ARRAY_BUFFER, model_vbo);
            defer C.glBindBuffer(C.GL_ARRAY_BUFFER, 0);
            inline for (@typeInfo(@TypeOf(model_va[0])).Struct.fields, 0..) |field, i| {
                C.glVertexAttribPointer(
                    i,
                    switch (@typeInfo(field.type).Array.len) {
                        1, 2, 3, 4 => |v| v,
                        else => {
                            @compileError("unhandled length for " ++ field.name);
                        },
                    },
                    switch (@typeInfo(field.type).Array.child) {
                        u8 => C.GL_UNSIGNED_BYTE,
                        u16 => C.GL_UNSIGNED_SHORT,
                        u32 => C.GL_UNSIGNED_INT,
                        i8 => C.GL_BYTE,
                        i16 => C.GL_SHORT,
                        i32 => C.GL_INT,
                        f32 => C.GL_FLOAT,
                        f64 => C.GL_DOUBLE,
                        else => {
                            @compileError("unhandled element type for " ++ field.name);
                        },
                    },
                    switch (@typeInfo(field.type).Array.child) {
                        u8, u16, u32, i8, i16, i32 => C.GL_TRUE,
                        f32 => C.GL_FALSE,
                        else => {
                            @compileError("unhandled normalisation for " ++ field.name);
                        },
                    },
                    @sizeOf(@TypeOf(model_va[0])),
                    &(@field(@intToPtr(*allowzero @TypeOf(model_va[0]), 0), field.name)),
                );
                C.glEnableVertexAttribArray(i);
            }
            C.glDrawArrays(C.GL_TRIANGLES, 0, 3);
        }

        gfx.flip();
        C.SDL_Delay(10);
        var ev: C.SDL_Event = undefined;
        if (C.SDL_PollEvent(&ev) != 0) {
            switch (ev.type) {
                C.SDL_QUIT => {
                    break :done;
                },
                else => {},
            }
        }
    }
}
