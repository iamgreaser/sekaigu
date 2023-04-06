const std = @import("std");
const log = std.log.scoped(.main);
const C = @import("c.zig");

const GfxContext = @import("GfxContext.zig");
const gl = @import("gl.zig");
const linalg = @import("linalg.zig");
const Vec2f = linalg.Vec2f;
const Vec3f = linalg.Vec3f;
const Vec4f = linalg.Vec4f;
const Mat2f = linalg.Mat2f;
const Mat3f = linalg.Mat3f;
const Mat4f = linalg.Mat4f;

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
    attrib_type: type,
    uniform_type: type,
    varyings: []const FieldEntry = &[_]FieldEntry{},
};
pub const ShaderSourceBlob = struct {
    vert_src: []const u8,
    frag_src: []const u8,
};

pub fn zigTypeToGlslType(comptime T: type, comptime exact: bool) []const u8 {
    return switch (T) {
        u8, i8, u16, i16 => if (exact) "int" else "float",
        f32 => "float",
        Vec2f => if (exact) "vec2" else "vec4",
        Vec3f => if (exact) "vec3" else "vec4",
        Vec4f => if (exact) "vec4" else "vec4",
        Mat2f => "mat2",
        Mat3f => "mat3",
        Mat4f => "mat4",
        else => switch (@typeInfo(T)) {
            .Array => |U| switch (U.child) {
                f32, u8, i8, u16, i16 => switch (U.len) {
                    1 => "float",
                    2 => if (exact) "vec2" else "vec4",
                    3 => if (exact) "vec3" else "vec4",
                    4 => if (exact) "vec4" else "vec4",
                    else => @compileError("invalid array length for conversion to GLSL"),
                },
                else => @compileError("unhandled array type for conversion to GLSL"),
            },
            else => @compileError("unhandled type for conversion to GLSL"),
        },
    };
}

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
fn _makeStructFieldList(
    comptime accum: []const u8,
    comptime prefix: []const u8,
    comptime name_prefix: []const u8,
    comptime fields: []const std.builtin.Type.StructField,
    comptime exact: bool,
) []const u8 {
    if (fields.len >= 1) {
        return _makeStructFieldList(
            accum ++ prefix ++ " " ++ zigTypeToGlslType(fields[0].type, exact) ++ " " ++ (name_prefix ++ fields[0].name) ++ ";\n",
            prefix,
            name_prefix,
            fields[1..],
            exact,
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
    const uniforms = _makeStructFieldList("", "uniform", "", @typeInfo(opts.uniform_type).Struct.fields, true);
    const attribs = _makeStructFieldList("", "attribute", "i", @typeInfo(opts.attrib_type).Struct.fields, false);
    const varyings = _makeFieldList("", "varying", opts.varyings);
    const commonheader = versionblock ++ uniforms;
    return ShaderSourceBlob{
        .vert_src = commonheader ++ attribs ++ varyings ++ opts.vert,
        .frag_src = commonheader ++ varyings ++ opts.frag,
    };
}

pub fn loadUniforms(program: gl.Program, comptime T: type, uniforms: *const T) !void {
    inline for (@typeInfo(T).Struct.fields) |field| {
        try program.uniform(field.name, field.type, @field(uniforms, field.name));
    }
}
var shader_uniforms: struct {
    zrot: f32 = 0.0,
    tintcolor: Vec4f = Vec4f.new(.{ 1.0, 0.8, 1.0, 1.0 }),
    mproj: Mat4f = Mat4f.I,
    mcam: Mat4f = Mat4f.I,
    mmodel: Mat4f = Mat4f.I,
} = .{};
const shader_src = makeShaderSource(.{
    .uniform_type = @TypeOf(shader_uniforms),
    .attrib_type = VA_P3F_C3F,
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
        \\    gl_FragColor = vcolor * tintcolor;
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

    done: while (true) {
        try gl.clearColor(0.2, 0.0, 0.4, 0.0);
        try gl.clear(.{ .color = true, .depth = true });
        {
            try gl.useProgram(shader_prog);
            defer gl.unuseProgram() catch {};
            try loadUniforms(shader_prog, @TypeOf(shader_uniforms), &shader_uniforms);

            try model_base.draw(.Triangles);
        }

        gfx.flip();
        shader_uniforms.zrot = @mod(shader_uniforms.zrot + 3.141593 * 2.0 / 3.0 / 60.0, 3.141593 * 2.0);
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
