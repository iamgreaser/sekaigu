const builtin = @import("builtin");
const std = @import("std");
const log = std.log.scoped(.main);
const time = std.time;
const C = @import("c.zig");

// FIXME: The dispatch seems borked --GM
//const GfxContext = @import("GfxContext.zig");
const GfxContext = if (builtin.target.isWasm())
    @import("GfxContext/web.zig")
else
    @import("GfxContext/sdl.zig");

const gl = @import("gl.zig");
const shadermagic = @import("shadermagic.zig");
const linalg = @import("linalg.zig");
const Vec2f = linalg.Vec2f;
const Vec3f = linalg.Vec3f;
const Vec4f = linalg.Vec4f;
const Mat2f = linalg.Mat2f;
const Mat3f = linalg.Mat3f;
const Mat4f = linalg.Mat4f;
const world = @import("world.zig");

const MAX_FPS = 60;
const NSEC_PER_FRAME = @divFloor(time.ns_per_s, MAX_FPS);

const TIMERS_EXIST = !builtin.target.isWasm(); // TODO! --GM
const DUMMY_TIMER = (struct {
    pub const Self = @This();
    pub fn read(self: Self) u64 {
        _ = self;
        return 0;
    }
    pub fn lap(self: Self) u64 {
        _ = self;
        return NSEC_PER_FRAME;
    }
}){};

pub const std_options = if (builtin.target.isWasm()) struct {
    // Provide a default log
    pub fn logFn(
        comptime level: std.log.Level,
        comptime scope: @TypeOf(.EnumLiteral),
        comptime format: []const u8,
        args: anytype,
    ) void {
        // TODO: Handle the other things --GM
        _ = level;
        _ = scope;

        // Here's an overkill temp buffer.
        var tmpbuf: [10 * 1024]u8 = undefined;
        C.console_log(std.fmt.bufPrintZ(&tmpbuf, format, args) catch "ERROR: LOG LINE TOO LONG");
    }
} else struct {
    //
};

pub const VA_P4HF_T2F_C3F_N3F = world.VA_P4HF_T2F_C3F_N3F;

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

var model_floor = Model(VA_P4HF_T2F_C3F_N3F, u16){
    .va = &[_]VA_P4HF_T2F_C3F_N3F{
        .{ .pos = .{ 0.0, 0.0, 0.0, 1.0 }, .tex0 = .{ 0, 0 }, .color = .{ 1.0, 1.0, 1.0 }, .normal = .{ 0, 1, 0 } },
        .{ .pos = .{ 0.0, 0.0, -1.0, 0.0 }, .tex0 = .{ 0, -1 }, .color = .{ 0, 0, 0 }, .normal = .{ 0, 0, 0 } },
        .{ .pos = .{ -1.0, 0.0, 1.0, 0.0 }, .tex0 = .{ -1, 1 }, .color = .{ 0, 0, 0 }, .normal = .{ 0, 0, 0 } },
        .{ .pos = .{ 1.0, 0.0, 1.0, 0.0 }, .tex0 = .{ 1, 1 }, .color = .{ 0, 0, 0 }, .normal = .{ 0, 0, 0 } },
    },
    .idx_list = &[_]u16{
        0, 1, 2,
        0, 2, 3,
        0, 3, 1,
    },
};

var model_base = Model(VA_P4HF_T2F_C3F_N3F, u16){
    .va = &[_]VA_P4HF_T2F_C3F_N3F{
        // Z- Rear
        .{ .pos = .{ -1.0, -1.0, -1.0, 1.0 }, .tex0 = .{ 0.0, 0.0 }, .color = .{ 0.5, 0.5, 0.5 }, .normal = .{ 0, 0, -1 } },
        .{ .pos = .{ -1.0, 1.0, -1.0, 1.0 }, .tex0 = .{ 0.0, 0.0 }, .color = .{ 0.5, 1.0, 0.5 }, .normal = .{ 0, 0, -1 } },
        .{ .pos = .{ 1.0, -1.0, -1.0, 1.0 }, .tex0 = .{ 0.0, 0.0 }, .color = .{ 1.0, 0.5, 0.5 }, .normal = .{ 0, 0, -1 } },
        .{ .pos = .{ 1.0, 1.0, -1.0, 1.0 }, .tex0 = .{ 0.0, 0.0 }, .color = .{ 1.0, 1.0, 0.5 }, .normal = .{ 0, 0, -1 } },
        // Z+ Front
        .{ .pos = .{ -1.0, -1.0, 1.0, 1.0 }, .tex0 = .{ 0.0, 0.0 }, .color = .{ 0.5, 0.5, 1.0 }, .normal = .{ 0, 0, 1 } },
        .{ .pos = .{ 1.0, -1.0, 1.0, 1.0 }, .tex0 = .{ 0.0, 0.0 }, .color = .{ 1.0, 0.5, 1.0 }, .normal = .{ 0, 0, 1 } },
        .{ .pos = .{ -1.0, 1.0, 1.0, 1.0 }, .tex0 = .{ 0.0, 0.0 }, .color = .{ 0.5, 1.0, 1.0 }, .normal = .{ 0, 0, 1 } },
        .{ .pos = .{ 1.0, 1.0, 1.0, 1.0 }, .tex0 = .{ 0.0, 0.0 }, .color = .{ 1.0, 1.0, 1.0 }, .normal = .{ 0, 0, 1 } },
        // X-
        .{ .pos = .{ -1.0, -1.0, -1.0, 1.0 }, .tex0 = .{ 0.0, 0.0 }, .color = .{ 0.5, 0.5, 0.5 }, .normal = .{ -1, 0, 0 } },
        .{ .pos = .{ -1.0, -1.0, 1.0, 1.0 }, .tex0 = .{ 0.0, 0.0 }, .color = .{ 0.5, 0.5, 1.0 }, .normal = .{ -1, 0, 0 } },
        .{ .pos = .{ -1.0, 1.0, -1.0, 1.0 }, .tex0 = .{ 0.0, 0.0 }, .color = .{ 0.5, 1.0, 0.5 }, .normal = .{ -1, 0, 0 } },
        .{ .pos = .{ -1.0, 1.0, 1.0, 1.0 }, .tex0 = .{ 0.0, 0.0 }, .color = .{ 0.5, 1.0, 1.0 }, .normal = .{ -1, 0, 0 } },
        // X+
        .{ .pos = .{ 1.0, -1.0, -1.0, 1.0 }, .tex0 = .{ 0.0, 0.0 }, .color = .{ 1.0, 0.5, 0.5 }, .normal = .{ 1, 0, 0 } },
        .{ .pos = .{ 1.0, 1.0, -1.0, 1.0 }, .tex0 = .{ 0.0, 0.0 }, .color = .{ 1.0, 1.0, 0.5 }, .normal = .{ 1, 0, 0 } },
        .{ .pos = .{ 1.0, -1.0, 1.0, 1.0 }, .tex0 = .{ 0.0, 0.0 }, .color = .{ 1.0, 0.5, 1.0 }, .normal = .{ 1, 0, 0 } },
        .{ .pos = .{ 1.0, 1.0, 1.0, 1.0 }, .tex0 = .{ 0.0, 0.0 }, .color = .{ 1.0, 1.0, 1.0 }, .normal = .{ 1, 0, 0 } },
        // Y-
        .{ .pos = .{ -1.0, -1.0, -1.0, 1.0 }, .tex0 = .{ 0.0, 0.0 }, .color = .{ 0.5, 0.5, 0.5 }, .normal = .{ 0, -1, 0 } },
        .{ .pos = .{ 1.0, -1.0, -1.0, 1.0 }, .tex0 = .{ 0.0, 0.0 }, .color = .{ 1.0, 0.5, 0.5 }, .normal = .{ 0, -1, 0 } },
        .{ .pos = .{ -1.0, -1.0, 1.0, 1.0 }, .tex0 = .{ 0.0, 0.0 }, .color = .{ 0.5, 0.5, 1.0 }, .normal = .{ 0, -1, 0 } },
        .{ .pos = .{ 1.0, -1.0, 1.0, 1.0 }, .tex0 = .{ 0.0, 0.0 }, .color = .{ 1.0, 0.5, 1.0 }, .normal = .{ 0, -1, 0 } },
        // Y+
        .{ .pos = .{ -1.0, 1.0, -1.0, 1.0 }, .tex0 = .{ 0.0, 0.0 }, .color = .{ 0.5, 1.0, 0.5 }, .normal = .{ 0, 1, 0 } },
        .{ .pos = .{ -1.0, 1.0, 1.0, 1.0 }, .tex0 = .{ 0.0, 0.0 }, .color = .{ 0.5, 1.0, 1.0 }, .normal = .{ 0, 1, 0 } },
        .{ .pos = .{ 1.0, 1.0, -1.0, 1.0 }, .tex0 = .{ 0.0, 0.0 }, .color = .{ 1.0, 1.0, 0.5 }, .normal = .{ 0, 1, 0 } },
        .{ .pos = .{ 1.0, 1.0, 1.0, 1.0 }, .tex0 = .{ 0.0, 0.0 }, .color = .{ 1.0, 1.0, 1.0 }, .normal = .{ 0, 1, 0 } },
    },
    .idx_list = &[_]u16{
        0,  1,  2,  2,  1,  3,
        4,  5,  6,  6,  5,  7,
        8,  9,  10, 10, 9,  11,
        12, 13, 14, 14, 13, 15,
        16, 17, 18, 18, 17, 19,
        20, 21, 22, 22, 21, 23,
    },
};

var shader_uniforms: struct {
    mproj: Mat4f = Mat4f.perspective(800.0, 600.0, 0.01, 1000.0),
    mcam: Mat4f = Mat4f.I,
    mmodel: Mat4f = Mat4f.I,
    light: Vec4f = Vec4f.new(.{ 0.0, 0.0, 0.0, 1.0 }),
    cam_pos: Vec4f = Vec4f.new(.{ 0.0, 0.0, 0.0, 1.0 }),
    smp0: gl.Sampler2D = gl.Sampler2D.makeSampler(0),
} = .{};
const shader_src = shadermagic.makeShaderSource(.{
    .uniform_type = @TypeOf(shader_uniforms),
    .attrib_type = VA_P4HF_T2F_C3F_N3F,
    .varyings = &[_]shadermagic.MakeShaderSourceOptions.FieldEntry{
        .{ "vec4", "vcolor" },
        .{ "vec4", "vwpos" },
        .{ "vec3", "vnormal" },
    },
    .vert = (
        \\vec3 vec3zeroclamp (vec3 v) {
        \\    const float CLAMPTHRESH = 1.0/126.0;
        \\    return sign(v)*max(abs(v)-CLAMPTHRESH,0.0)/(1.0-CLAMPTHRESH);
        \\}
        \\
        \\void main () {
        \\    vcolor = icolor;
        \\    vec4 rwpos = mmodel * ipos;
        \\    vec4 rpos = mproj * mcam * rwpos;
        \\    vec4 rnormal = vec4(inormal.xyz, 0.0);
        \\    vwpos = rwpos;
        \\    vnormal = (mmodel * rnormal).xyz;
        \\    gl_Position = rpos;
        \\}
    ),
    .frag = (
        \\void main () {
        \\    const vec3 Ma = vec3(0.1);
        \\    const vec3 Md = vec3(0.9);
        \\    const vec3 Ms = vec3(0.8);
        \\    const float MsExp = 64.0;
        \\    vec3 wpos = vwpos.xyz/vwpos.w;
        \\    vec4 vtxcolor = vec4(vcolor.rgb/vwpos.w, vcolor.a);
        \\    vec4 color = vtxcolor;
        \\    vec3 normal = normalize(vnormal/vwpos.w);
        \\    vec3 vlightdir = normalize(light.xyz - wpos*light.w);
        \\    vec3 ambdiff = Ma + Md*max(0.0, dot(vlightdir, normal));
        \\    vec3 vcamdir = normalize(cam_pos.xyz - wpos);
        \\    vec3 vspecdir = 2.0*normal*dot(normal, vlightdir) - vlightdir;
        \\    vec3 spec = Ms*pow(max(0.0, dot(vcamdir, vspecdir)), MsExp);
        \\    gl_FragColor = vec4((color.rgb*ambdiff)+spec, color.a);
        \\}
    ),
});
var shader_prog: gl.Program = gl.Program.Dummy;
var shader_prog_unicache: shadermagic.UniformIdxCache(@TypeOf(shader_uniforms)) = .{};

const floor_shader_src = shadermagic.makeShaderSource(.{
    .uniform_type = @TypeOf(shader_uniforms),
    .attrib_type = VA_P4HF_T2F_C3F_N3F,
    .varyings = &[_]shadermagic.MakeShaderSourceOptions.FieldEntry{
        .{ "vec4", "vwpos" },
        .{ "vec2", "vtex0" },
        .{ "vec4", "vcolor" },
        .{ "vec3", "vnormal" },
    },
    .vert = (
        \\vec2 vec2zeroclamp (vec2 v) {
        \\    const float CLAMPTHRESH = 1.0/126.0;
        \\    return sign(v)*max(abs(v)-CLAMPTHRESH,0.0)/(1.0-CLAMPTHRESH);
        \\}
        \\
        \\vec3 vec3zeroclamp (vec3 v) {
        \\    const float CLAMPTHRESH = 1.0/126.0;
        \\    return sign(v)*max(abs(v)-CLAMPTHRESH,0.0)/(1.0-CLAMPTHRESH);
        \\}
        \\
        \\void main () {
        \\    vtex0 = itex0.st;
        \\    vcolor = icolor;
        \\    vec4 rwpos = mmodel * ipos;
        \\    vec4 rpos = mproj * mcam * rwpos;
        \\    vec4 rnormal = vec4(inormal.xyz, 0.0);
        \\    vwpos = rwpos;
        \\    vnormal = (mmodel * rnormal).xyz;
        \\    gl_Position = rpos;
        \\}
    ),
    .frag = (
        \\void main () {
        \\    const vec3 Ma = vec3(0.1);
        \\    const vec3 Md = vec3(0.9);
        \\    const vec3 Ms = vec3(0.8);
        \\    const float MsExp = 64.0;
        \\    vec3 wpos = vwpos.xyz/vwpos.w;
        \\    vec2 tex0 = vtex0/vwpos.w;
        \\    vec4 vtxcolor = vec4(vcolor.rgb/vwpos.w, vcolor.a);
        \\    vec4 t0color = texture2D(smp0, tex0);
        \\    vec4 color = t0color*vtxcolor;
        \\    vec3 normal = normalize(vnormal/vwpos.w);
        \\    vec3 vlightdir = normalize(light.xyz - wpos*light.w);
        \\    vec3 ambdiff = Ma + Md*max(0.0, dot(vlightdir, normal));
        \\    vec3 vcamdir = normalize(cam_pos.xyz - wpos);
        \\    vec3 vspecdir = 2.0*normal*dot(normal, vlightdir) - vlightdir;
        \\    vec3 spec = Ms*pow(max(0.0, dot(vcamdir, vspecdir)), MsExp);
        \\    gl_FragColor = vec4((color.rgb*ambdiff)+spec, vcolor.a);
        \\}
    ),
});
var floor_shader_prog: gl.Program = gl.Program.Dummy;
var floor_shader_prog_unicache: shadermagic.UniformIdxCache(@TypeOf(shader_uniforms)) = .{};

var test_tex: gl.Texture2D = gl.Texture2D.Dummy;
var gfx: GfxContext = undefined;

var timer: if (TIMERS_EXIST) time.Timer else @TypeOf(DUMMY_TIMER) = undefined;
var time_accum: u64 = 0;
var frame_time_accum: i64 = 0;
var fps_time_accum: u64 = 0;
var fps_counter: u64 = 0;
pub fn init() !void {
    // Create a graphics context
    gfx = try GfxContext.new();
    try gfx.init();
    errdefer gfx.free();

    // Compile the shaders
    shader_prog = try shader_src.compileProgram();
    floor_shader_prog = try floor_shader_src.compileProgram();

    // Generate a test texture
    test_tex = try gl.Texture2D.genTexture();
    {
        const SHIFT = 8;
        const SIZE = 1 << SHIFT;
        var buf: [SIZE * SIZE]u32 = undefined;
        for (0..SIZE) |y| {
            for (0..SIZE) |x| {
                //var v: u32 = (@intCast(u32, x ^ y)) << (8 - SHIFT);
                //if (SHIFT < 8) v |= (v >> SHIFT);
                //var v: u32 = if ((x >= (SIZE >> 1)) == (y >= (SIZE >> 1))) 0xFF else 0x10;
                var v: u32 = if ((x < 8) or (y < 8) or (((x * 5) % SIZE) < 3 * 5) or (((y * 5) % SIZE) < 3 * 5)) 0x10 else 0xFF;
                v *= 0x00010101;
                v &= 0x00FFFFFF;
                v |= 0xFF000000;
                buf[y * SIZE + x] = v;
            }
        }
        defer gl.activeTexture(0) catch {};
        try gl.activeTexture(0);
        defer {
            // FIXME: if activeTexture somehow fails, this may unbind the wrong slot --GM
            gl.activeTexture(0) catch {};
            gl.Texture2D.unbindTexture() catch {};
        }
        try gl.Texture2D.bindTexture(test_tex);
        // TODO: Add bindings for texture parameters --GM
        C.glTexParameteri(C.GL_TEXTURE_2D, C.GL_TEXTURE_WRAP_S, C.GL_REPEAT);
        C.glTexParameteri(C.GL_TEXTURE_2D, C.GL_TEXTURE_WRAP_T, C.GL_REPEAT);
        C.glTexParameteri(C.GL_TEXTURE_2D, C.GL_TEXTURE_MAG_FILTER, C.GL_NEAREST);
        C.glTexParameteri(C.GL_TEXTURE_2D, C.GL_TEXTURE_MIN_FILTER, C.GL_LINEAR_MIPMAP_LINEAR);
        //C.glTexParameteri(C.GL_TEXTURE_2D, C.GL_TEXTURE_MIN_FILTER, C.GL_NEAREST);
        // TODO: Detect the GL_EXT_texture_filter_anisotropic extension --GM
        //C.glTexParameteri(C.GL_TEXTURE_2D, C.GL_TEXTURE_MAX_ANISOTROPY_EXT, 16);
        try gl._TestError();
        try gl.Texture2D.texImage2D(0, SIZE, SIZE, .RGBA8888, &buf);
        try gl.Texture2D.generateMipmap();
    }

    // Load the VBOs
    try model_base.load();
    try model_floor.load();

    // Bind our test texture
    try shader_uniforms.smp0.bindTexture(test_tex);

    // Start our timer
    timer = if (TIMERS_EXIST) try time.Timer.start() else DUMMY_TIMER;
}

pub fn destroy() void {
    gfx.free();
}

pub fn main() !void {
    try init();
    defer destroy();

    var dt: f32 = 0.0;
    done: while (true) {
        fps_counter += 1;
        try drawScene();
        gfx.flip();
        try tickScene(dt);
        if (try gfx.applyEvents(@TypeOf(keys), &keys)) {
            break :done;
        }
        dt = try updateTime();
    }
}

var model_zrot: f32 = 0.0;
var cam_rot: Vec4f = Vec4f.new(.{ 0.0, 0.0, 0.0, 1.0 });
var cam_pos: Vec4f = Vec4f.new(.{ 0.0, 0.0, 0.0, 1.0 });
var cam_drot: Vec4f = Vec4f.new(.{ 0.0, 0.0, 0.0, 0.0 });
var cam_dpos: Vec4f = Vec4f.new(.{ 0.0, 0.0, 0.0, 0.0 });
var keys: struct {
    w: bool = false,
    a: bool = false,
    s: bool = false,
    d: bool = false,
    c: bool = false,
    SPACE: bool = false,
    LEFT: bool = false,
    RIGHT: bool = false,
    UP: bool = false,
    DOWN: bool = false,
} = .{};

pub fn tickScene(dt: f32) !void {
    model_zrot = @mod(model_zrot + 3.141593 * 2.0 / 5.0 * dt, 3.141593 * 2.0);
    cam_dpos = Vec4f.new(.{
        if (keys.d) @as(f32, 1.0) else @as(f32, 0.0),
        if (keys.SPACE) @as(f32, 1.0) else @as(f32, 0.0),
        if (keys.s) @as(f32, 1.0) else @as(f32, 0.0),
        0.0,
    }).sub(Vec4f.new(.{
        if (keys.a) @as(f32, 1.0) else @as(f32, 0.0),
        if (keys.c) @as(f32, 1.0) else @as(f32, 0.0),
        if (keys.w) @as(f32, 1.0) else @as(f32, 0.0),
        0.0,
    })).mul(5.0);
    cam_drot = Vec4f.new(.{
        if (keys.DOWN) @as(f32, 1.0) else @as(f32, 0.0),
        if (keys.RIGHT) @as(f32, 1.0) else @as(f32, 0.0),
        0.0,
        0.0,
    }).sub(Vec4f.new(.{
        if (keys.UP) @as(f32, 1.0) else @as(f32, 0.0),
        if (keys.LEFT) @as(f32, 1.0) else @as(f32, 0.0),
        0.0,
        0.0,
    })).mul(3.141593); // 180 deg per second

    // TODO: Have a matrix invert function --GM
    const icam = Mat4f.I
        .translate(cam_pos.a[0], cam_pos.a[1], cam_pos.a[2])
        .rotate(-cam_rot.a[1], 0.0, 1.0, 0.0)
        .rotate(-cam_rot.a[0], 1.0, 0.0, 0.0);
    cam_pos = cam_pos.add(icam.mul(cam_dpos.mul(dt)));
    cam_rot = cam_rot.add(cam_drot.mul(dt));
}

pub fn drawScene() !void {
    shader_uniforms.mproj = Mat4f.perspective(
        @intToFloat(f32, gfx.width),
        @intToFloat(f32, gfx.height),
        0.01,
        1000.0,
    );
    try gl.clearColor(0.2, 0.0, 0.4, 0.0);
    try gl.clear(.{ .color = true, .depth = true });
    shader_uniforms.cam_pos = cam_pos;
    shader_uniforms.mcam = Mat4f.I
        .rotate(cam_rot.a[0], 1.0, 0.0, 0.0)
        .rotate(cam_rot.a[1], 0.0, 1.0, 0.0)
        .translate(-cam_pos.a[0], -cam_pos.a[1], -cam_pos.a[2]);
    shader_uniforms.light = cam_pos;
    {
        const had_DepthTest = try gl.isEnabled(.DepthTest);
        const had_CullFace = try gl.isEnabled(.CullFace);
        defer gl.setEnabled(.DepthTest, had_DepthTest) catch {};
        defer gl.setEnabled(.CullFace, had_CullFace) catch {};
        try gl.enable(.DepthTest);
        try gl.enable(.CullFace);

        {
            try gl.useProgram(shader_prog);
            defer gl.unuseProgram() catch {};
            shader_uniforms.mmodel = Mat4f.I
                .translate(0.5, 0.0, -3.0)
                .rotate(model_zrot, 0.0, 1.0, 0.0)
                .rotate(model_zrot * 2.0, 0.0, 0.0, 1.0);
            try shadermagic.loadUniforms(&shader_prog, @TypeOf(shader_uniforms), &shader_uniforms, &shader_prog_unicache);
            try model_base.draw(.Triangles);
        }

        {
            defer gl.activeTexture(0) catch {};
            try gl.activeTexture(0);
            defer {
                // FIXME: if activeTexture somehow fails, this may unbind the wrong slot --GM
                gl.activeTexture(0) catch {};
                gl.Texture2D.unbindTexture() catch {};
            }
            try gl.Texture2D.bindTexture(test_tex);

            try gl.useProgram(floor_shader_prog);
            defer gl.unuseProgram() catch {};
            shader_uniforms.mmodel = Mat4f.I
                .translate(0.0, -2.0, 0.0);
            try shadermagic.loadUniforms(&floor_shader_prog, @TypeOf(shader_uniforms), &shader_uniforms, &floor_shader_prog_unicache);
            try model_floor.draw(.Triangles);
        }
    }
}

pub fn updateTime() !f32 {
    frame_time_accum += NSEC_PER_FRAME;
    const sleep_time = frame_time_accum - @intCast(i64, timer.read());
    if (sleep_time > 0) {
        if (comptime builtin.target.isWasm()) {
            // TODO! --GM
        } else {
            time.sleep(@intCast(u64, sleep_time));
        }
    }
    const dt_snap = timer.lap();
    time_accum += dt_snap;
    fps_time_accum += dt_snap;
    frame_time_accum -= @intCast(i64, dt_snap);
    if (frame_time_accum < 0) {
        // Seems we can't achieve the given rendering FPS.
        frame_time_accum = 0;
    }

    if (fps_time_accum >= (time.ns_per_s * 1)) {
        {
            //log.debug("FPS: {}", .{fps_counter});
            var buf: [128]u8 = undefined;
            gfx.setTitle(try std.fmt.bufPrintZ(&buf, "cockel pre-alpha | FPS: {}", .{fps_counter}));
        }
        if (fps_time_accum >= (time.ns_per_s * 1) * 2) {
            log.warn("FPS counter slipped! Time wasted (nsec): {}", .{fps_time_accum});
        }
        fps_time_accum %= (time.ns_per_s * 1);
        fps_counter = 0;
    }
    return @floatCast(f32, @intToFloat(f64, dt_snap) / @intToFloat(f64, time.ns_per_s * 1));
}

export fn c_init() bool {
    init() catch {
        return false;
    };
    return true;
}

export fn c_destroy() void {
    destroy();
}

export fn c_drawScene() bool {
    drawScene() catch {
        return false;
    };
    return true;
}

export fn c_tickScene(dt: f32) bool {
    tickScene(dt) catch {
        return false;
    };
    return true;
}

export fn c_applyEvents() bool {
    return gfx.applyEvents(@TypeOf(keys), &keys) catch true;
}

export fn c_handleResize(width: i32, height: i32) bool {
    gfx.handleResize(width, height) catch {
        return false;
    };
    return true;
}
