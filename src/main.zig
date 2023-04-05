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
var model_vbo: gl.BO = gl.BO.Dummy;

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
        model_vbo = try gl.genBuffer();
        try gl.bindBuffer(.ArrayBuffer, model_vbo);
        defer gl.unbindBuffer(.ArrayBuffer) catch {};
        try gl.bufferData(.ArrayBuffer, model_va, .StaticDraw);
    }

    done: while (true) {
        try gl.clearColor(0.2, 0.0, 0.4, 0.0);
        try gl.clear(.{ .color = true, .depth = true });
        {
            try gl.useProgram(shader_prog);
            defer gl.unuseProgram() catch {};

            try gl.bindBuffer(.ArrayBuffer, model_vbo);
            defer gl.unbindBuffer(.ArrayBuffer) catch {};

            defer {
                inline for (@typeInfo(@TypeOf(model_va[0])).Struct.fields, 0..) |_, i| {
                    gl.disableVertexAttribArray(i) catch {};
                }
            }
            inline for (@typeInfo(@TypeOf(model_va[0])).Struct.fields, 0..) |field, i| {
                try gl.vertexAttribPointer(i, model_va, field.name);
                try gl.enableVertexAttribArray(i);
            }
            try gl.drawArrays(.Triangles, 0, 3);
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
