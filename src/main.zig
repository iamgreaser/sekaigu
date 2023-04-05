const std = @import("std");
const log = std.log.scoped(.main);
const C = @import("c.zig");

const GfxContext = @import("GfxContext.zig");
const gl = @import("gl.zig");

pub const VA_P3F_C3F = struct {
    pos: [3]f32,
    color: [3]u8,
};

pub fn Model(comptime VAType: type, comptime IdxType: type) type {
    return struct {
        pub const Self = @This();

        va: []const VAType,
        idx_list: []const IdxType,
        va_vbo: gl.BO = gl.BO.Dummy,
        idx_vbo: gl.BO = gl.BO.Dummy,

        pub fn load(self: *Self) !void {
            {
                self.va_vbo = try gl.BO.genBuffer();
                try gl.bindBuffer(.ArrayBuffer, self.va_vbo);
                defer gl.unbindBuffer(.ArrayBuffer) catch {};
                try gl.bufferData(.ArrayBuffer, VAType, self.va, .StaticDraw);
            }
            {
                self.idx_vbo = try gl.BO.genBuffer();
                try gl.bindBuffer(.ElementArrayBuffer, self.idx_vbo);
                defer gl.unbindBuffer(.ElementArrayBuffer) catch {};
                try gl.bufferData(.ElementArrayBuffer, IdxType, self.idx_list, .StaticDraw);
            }
        }

        pub fn draw(
            self: Self,
            mode: gl.DrawMode,
        ) !void {
            try gl.bindBuffer(.ArrayBuffer, self.va_vbo);
            defer gl.unbindBuffer(.ArrayBuffer) catch {};
            try gl.bindBuffer(.ElementArrayBuffer, self.idx_vbo);
            defer gl.unbindBuffer(.ElementArrayBuffer) catch {};

            defer {
                inline for (@typeInfo(VAType).Struct.fields, 0..) |_, i| {
                    gl.disableVertexAttribArray(i) catch {};
                }
            }
            inline for (@typeInfo(VAType).Struct.fields, 0..) |field, i| {
                try gl.vertexAttribPointer(i, VAType, field.name);
                try gl.enableVertexAttribArray(i);
            }
            try gl.drawElements(mode, 0, self.idx_list.len, IdxType);
            //try gl.drawArrays(mode, 0, self.va.len);
        }
    };
}

var model_base = Model(VA_P3F_C3F, u16){
    .va = &[_]VA_P3F_C3F{
        .{ .pos = .{ 0.00, 0.99, 0.00 }, .color = .{ 0xFF, 0x80, 0x80 } },
        .{ .pos = .{ -0.70, -0.50, 0.00 }, .color = .{ 0x80, 0xFF, 0x80 } },
        .{ .pos = .{ 0.70, -0.50, 0.00 }, .color = .{ 0x80, 0x80, 0xFF } },
    },
    .idx_list = &[_]u16{ 0, 1, 2 },
};

pub const MakeShaderSourceOptions = struct {
    pub const FieldEntry = struct {
        @"0": []const u8,
        @"1": []const u8,
    };
    vert: []const u8,
    frag: []const u8,
    uniforms: []const FieldEntry = &[_]FieldEntry{},
    attribs: []const FieldEntry = &[_]FieldEntry{},
    varyings: []const FieldEntry = &[_]FieldEntry{},
};
pub const ShaderSourceBlob = struct {
    vert_src: []const u8,
    frag_src: []const u8,
};

fn _makeFieldList(
    comptime accum: []const u8,
    comptime prefix: []const u8,
    comptime fields: []const MakeShaderSourceOptions.FieldEntry,
) []const u8 {
    if (fields.len >= 1) {
        return _makeFieldList(
            accum ++ prefix ++ " " ++ fields[0].@"0" ++ " " ++ fields[0].@"1" ++ ";\n",
            prefix,
            fields[1..],
        );
    } else {
        return accum;
    }
}
pub fn makeShaderSource(comptime opts: MakeShaderSourceOptions) ShaderSourceBlob {
    const versionblock =
        \\#version 100
        \\precision highp float;
        \\
    ;
    const uniforms = _makeFieldList("", "uniform", opts.uniforms);
    const attribs = _makeFieldList("", "attribute", opts.attribs);
    const varyings = _makeFieldList("", "varying", opts.varyings);
    const commonheader = versionblock ++ uniforms;
    return ShaderSourceBlob{
        .vert_src = commonheader ++ attribs ++ varyings ++ opts.vert,
        .frag_src = commonheader ++ varyings ++ opts.frag,
    };
}

const shader_src = makeShaderSource(.{
    .uniforms = &[_]MakeShaderSourceOptions.FieldEntry{
        .{ "float", "zrot" },
    },
    .attribs = &[_]MakeShaderSourceOptions.FieldEntry{
        .{ "vec4", "ipos" },
        .{ "vec4", "icolor" },
    },
    .varyings = &[_]MakeShaderSourceOptions.FieldEntry{
        .{ "vec4", "vcolor" },
    },
    .vert = (
        \\void main () {
        \\    vcolor = icolor;
        \\    vec4 rpos = ipos;
        \\    rpos.xy = (rpos.xy * cos(zrot) + rpos.yx * vec2(1.0, -1.0) * sin(zrot));
        \\    rpos.x *= 600.0/800.0;
        \\    gl_Position = rpos;
        \\}
    ),
    .frag = (
        \\void main () {
        \\    gl_FragColor = vcolor;
        \\}
    ),
});
var shader_v: gl.Shader = gl.Shader.Dummy;
var shader_f: gl.Shader = gl.Shader.Dummy;
var shader_prog: gl.Program = gl.Program.Dummy;

pub fn main() !void {
    var gfx = try GfxContext.new();
    try gfx.init();
    defer gfx.free();

    // Compile the shader
    shader_prog = try gl.Program.createProgram();
    shader_v = try gl.Shader.createShader(.Vertex);
    shader_f = try gl.Shader.createShader(.Fragment);
    try shader_prog.attachShader(shader_v);
    try shader_prog.attachShader(shader_f);
    inline for (@typeInfo(@TypeOf(model_base.va[0])).Struct.fields, 0..) |field, i| {
        try shader_prog.bindAttribLocation(i, "i" ++ field.name);
    }
    try shader_v.shaderSource(shader_src.vert_src);
    try shader_f.shaderSource(shader_src.frag_src);
    try shader_v.compileShader();
    try shader_f.compileShader();
    try shader_prog.linkProgram();

    // Load the VBOs
    try model_base.load();

    var ang: f64 = 0.0;
    const uni_zrot = C.glGetUniformLocation(shader_prog.handle, "zrot");
    try gl._TestError();
    done: while (true) {
        try gl.clearColor(0.2, 0.0, 0.4, 0.0);
        try gl.clear(.{ .color = true, .depth = true });
        {
            try gl.useProgram(shader_prog);
            if (uni_zrot >= 0) {
                C.glUniform1f(uni_zrot, @floatCast(f32, ang));
                try gl._TestError();
            }
            defer gl.unuseProgram() catch {};

            try model_base.draw(.Triangles);
        }

        gfx.flip();
        ang = @mod(ang + 3.141593 * 2.0 / 3.0 / 60.0, 3.141593 * 2.0);
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
