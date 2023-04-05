const std = @import("std");
const log = std.log.scoped(.main);

const C = @import("c.zig");

const GfxContext = @import("GfxContext.zig");

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
var shader_v: C.GLuint = 0;
var shader_f: C.GLuint = 0;
var shader_prog: C.GLuint = 0;

pub fn main() !void {
    var gfx = try GfxContext.new();
    try gfx.init();
    defer gfx.free();

    log.warn("GL error status at start: {}", .{C.glGetError()});

    // Compile the shader
    shader_prog = C.glCreateProgram();
    shader_v = C.glCreateShader(C.GL_VERTEX_SHADER);
    shader_f = C.glCreateShader(C.GL_FRAGMENT_SHADER);
    C.glAttachShader(shader_prog, shader_v);
    C.glAttachShader(shader_prog, shader_f);
    inline for (@typeInfo(@TypeOf(model_va[0])).Struct.fields, 0..) |field, i| {
        C.glBindAttribLocation(shader_prog, i, "i" ++ field.name);
    }
    C.glShaderSource(shader_v, 1, &[_][*]const u8{shader_v_src}, &[_]C.GLint{shader_v_src.len});
    C.glShaderSource(shader_f, 1, &[_][*]const u8{shader_f_src}, &[_]C.GLint{shader_f_src.len});
    C.glCompileShader(shader_v);
    C.glCompileShader(shader_f);
    C.glLinkProgram(shader_prog);
    {
        var buf: [1024]u8 = undefined;
        var buflen: C.GLsizei = 0;
        C.glGetShaderInfoLog(shader_v, buf.len, &buflen, &buf);
        log.info("VERTEX SHADER LOG: <<<\n{s}\n>>>", .{buf[0..@intCast(usize, buflen)]});
        C.glGetShaderInfoLog(shader_f, buf.len, &buflen, &buf);
        log.info("FRAGMENT SHADER LOG: <<<\n{s}\n>>>", .{buf[0..@intCast(usize, buflen)]});
        C.glGetProgramInfoLog(shader_prog, buf.len, &buflen, &buf);
        log.info("PROGRAM LOG: <<<\n{s}\n>>>", .{buf[0..@intCast(usize, buflen)]});
    }
    log.warn("GL error status after shaders: {}", .{C.glGetError()});

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
            C.glUseProgram(shader_prog);
            defer C.glUseProgram(0);
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
