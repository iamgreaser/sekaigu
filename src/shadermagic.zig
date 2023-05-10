// SPDX-License-Identifier: AGPL-3.0-or-later
const std = @import("std");
const log = std.log.scoped(.shadermagic);
const gl = @import("gl.zig");
const C = @import("c.zig");
const linalg = @import("linalg.zig");
const Vec2f = linalg.Vec2f;
const Vec3f = linalg.Vec3f;
const Vec4f = linalg.Vec4f;
const Mat2f = linalg.Mat2f;
const Mat3f = linalg.Mat3f;
const Mat4f = linalg.Mat4f;

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
    pub const Self = @This();
    vert_src: [:0]const u8,
    frag_src: [:0]const u8,
    attrib_names: []const [:0]const u8,

    pub fn compileProgram(self: Self) !gl.Program {
        var shader_prog = try gl.Program.createProgram();
        const shader_v = try gl.Shader.createShader(.Vertex);
        const shader_f = try gl.Shader.createShader(.Fragment);
        try shader_prog.attachShader(shader_v);
        try shader_prog.attachShader(shader_f);
        for (self.attrib_names, 0..) |name, i| {
            try shader_prog.bindAttribLocation(@intCast(C.GLuint, i), name);
        }
        try shader_v.shaderSource(self.vert_src);
        try shader_f.shaderSource(self.frag_src);
        try shader_v.compileShader();
        try shader_f.compileShader();
        try shader_prog.linkProgram();
        return shader_prog;
    }
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
        gl.Sampler2D => "sampler2D",
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
fn _makeShaderNames(
    comptime accum: []const [:0]const u8,
    comptime fields: []const std.builtin.Type.StructField,
) []const [:0]const u8 {
    if (fields.len >= 1) {
        return _makeShaderNames(
            accum ++ [_][:0]const u8{"i" ++ fields[0].name},
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
    const uniforms = _makeStructFieldList("", "uniform", "", @typeInfo(opts.uniform_type).Struct.fields, true);
    const attribs = _makeStructFieldList("", "attribute", "i", @typeInfo(opts.attrib_type).Struct.fields, false);
    const varyings = _makeFieldList("", "varying", opts.varyings);
    const attrib_names = _makeShaderNames(&[_][:0]const u8{}, @typeInfo(opts.attrib_type).Struct.fields);
    const commonheader = versionblock ++ uniforms;
    return ShaderSourceBlob{
        .vert_src = commonheader ++ attribs ++ varyings ++ opts.vert,
        .frag_src = commonheader ++ varyings ++ opts.frag,
        .attrib_names = attrib_names,
    };
}

fn _UIC_fields(comptime accum: []const std.builtin.Type.StructField, comptime remain: []const std.builtin.Type.StructField) []const std.builtin.Type.StructField {
    if (remain.len == 0) {
        return accum;
    } else {
        return _UIC_fields(
            accum ++ [_]std.builtin.Type.StructField{
                std.builtin.Type.StructField{
                    .name = remain[0].name,
                    .type = C.GLint,
                    .default_value = &@as(C.GLint, -1),
                    .is_comptime = false,
                    .alignment = 1,
                },
            },
            remain[1..],
        );
    }
}
pub fn UniformIdxCache(comptime T: type) type {
    const fields = _UIC_fields(&[_]std.builtin.Type.StructField{}, @typeInfo(T).Struct.fields);
    return @Type(std.builtin.Type{ .Struct = std.builtin.Type.Struct{
        .layout = .Auto,
        .fields = fields,
        .decls = &[_]std.builtin.Type.Declaration{},
        .is_tuple = false,
    } });
}

pub fn loadUniforms(program: *gl.Program, comptime T: type, uniforms: *const T, uniformIdxCache: *UniformIdxCache(T)) !void {
    inline for (@typeInfo(T).Struct.fields) |field| {
        const nameZ = field.name[0..field.name.len :0];
        var idx = @field(uniformIdxCache, field.name);
        if (idx < 0) {
            idx = try program.getUniformLocation(nameZ);
            @field(uniformIdxCache, field.name) = idx;
        }
        try program.uniform(idx, field.type, @field(uniforms, field.name));
    }
}
