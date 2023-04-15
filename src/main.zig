const builtin = @import("builtin");
const std = @import("std");
const log = std.log.scoped(.main);
const time = std.time;
const Allocator = std.mem.Allocator;
const C = @import("c.zig");

const TICKS_PER_SEC = 20;

pub const main_allocator = if (builtin.target.isWasm())
    std.heap.wasm_allocator
else
    std.heap.c_allocator;

const GfxContext = @import("GfxContext.zig").GfxContext;

const WebServer = if (builtin.target.isWasm())
    struct {
        const Self = @This();

        pub fn init(self: *Self) !void {
            _ = self;
        }

        pub fn deinit(self: *Self) void {
            _ = self;
        }

        pub fn update(self: *Self) !void {
            _ = self;
        }
    }
else
    @import("WebServer.zig").WebServer;

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
const ConvexHull = world.ConvexHull;

const session_module = @import("session.zig");
const Session = session_module.Session;
const Player = session_module.Player;
const LocalPlayer = session_module.LocalPlayer;

const font_renderer = @import("font_renderer.zig");
const gfxstate = @import("gfxstate.zig");
const Model = gfxstate.Model;

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

    pub const log_level = .debug;
} else struct {
    pub const log_level = .debug;
};

pub const VA_P4HF_T2F_C3F_N3F = world.VA_P4HF_T2F_C3F_N3F;

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

var model_pyramid: ?Model(VA_P4HF_T2F_C3F_N3F, u16) = null;

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

const shader_src = shadermagic.makeShaderSource(.{
    .uniform_type = @TypeOf(gfxstate.shader_uniforms),
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
var shader_prog_unicache: shadermagic.UniformIdxCache(@TypeOf(gfxstate.shader_uniforms)) = .{};

const textured_src = shadermagic.makeShaderSource(.{
    .uniform_type = @TypeOf(gfxstate.shader_uniforms),
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
var textured_prog: gl.Program = gl.Program.Dummy;
var textured_prog_unicache: shadermagic.UniformIdxCache(@TypeOf(gfxstate.shader_uniforms)) = .{};

var test_tex: gl.Texture2D = gl.Texture2D.Dummy;
var gfx: GfxContext = undefined;
var webserver: WebServer = undefined;

var session: ?Session = null;

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

    // Initialise the font renderer
    try font_renderer.init(main_allocator);
    errdefer font_renderer.free();

    // Create a session and player
    errdefer ({
        if (session) |*s| {
            s.deinit();
            session = null;
        }
    });
    session = undefined;
    try session.?.init(.{
        .allocator = main_allocator,
    });
    local_player = try session.?.addPlayer(.{
        .player_type = .{
            .Local = &local_player_backing,
        },
    });
    errdefer ({
        session.?.removePlayer(local_player.?);
        local_player = null;
    });

    // Create a web server
    try webserver.init();
    errdefer webserver.deinit();

    // Compile the shaders
    shader_prog = try shader_src.compileProgram();
    textured_prog = try textured_src.compileProgram();

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

    // Bake our hulls into meshes
    model_pyramid = try Model(VA_P4HF_T2F_C3F_N3F, u16).fromConvexHullPlanes(main_allocator, &[_][4]f32{
        //.{ 0.0, -1.0, 0.0, 0.0 },
        //.{ -1.0, 1.0, 0.0, -5.0 / 2.0 },
        //.{ 1.0, 1.0, 0.0, -5.0 / 2.0 },
        //.{ 0.0, 1.0, -1.0, -5.0 / 2.0 },
        //.{ 0.0, 1.0, 1.0, -5.0 / 2.0 },
        .{ 0.0, 1.0, 0.0, -5.0 / 2.0 },
        //.{ -1.0, 1.0, 0.0, -5.0 / 2.0 },
        //.{ 1.0, 1.0, 0.0, -5.0 / 2.0 },
        .{ 0.0, 1.0, -1.0, -5.0 / 2.0 },
        .{ 0.0, 1.0, 1.0, -5.0 / 2.0 },
    });
    //log.warn("baked {any}", .{model_pyramid.?.va});
    //log.warn("baked {any}", .{model_pyramid.?.idx_list});

    // Load the VBOs
    try model_base.load();
    try model_floor.load();
    try model_pyramid.?.load();
    try font_renderer.model_fonttest.?.load();

    // Start our timer
    timer = if (TIMERS_EXIST) try time.Timer.start() else DUMMY_TIMER;
}

pub fn destroy() void {
    webserver.deinit();
    if (session) |*s| {
        if (local_player) |*p| {
            s.removePlayer(p.*);
        }
        s.deinit();
        session = null;
    }
    if (local_player != null) {
        local_player = null;
    }
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
        try webserver.update();
        if (try gfx.applyEvents(@TypeOf(keys), &keys)) {
            break :done;
        }
        dt = try updateTime();
    }
}

var model_zrot: f32 = 0.0;
var model_dzrot: f32 = 3.141593 * 2.0 / 5.0;
var local_player_backing: LocalPlayer = .{};
var local_player: ?*Player = null;
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

const SECS_PER_TICK: f32 = 1.0 / @intToFloat(f32, TICKS_PER_SEC);
var accum_tick_secs: f32 = 0.0;
pub fn tickScene(dt: f32) !void {
    accum_tick_secs += dt;
    while (accum_tick_secs >= SECS_PER_TICK) {
        try tickSceneReal(SECS_PER_TICK);
        accum_tick_secs -= SECS_PER_TICK;
    }
}

pub fn tickSceneReal(dt: f32) !void {
    model_zrot = @mod(model_zrot + model_dzrot * dt, 3.141593 * 2.0);
    const p: *Player = local_player.?;
    try tickPlayer(dt, p);
}

fn tickPlayer(dt: f32, p: *Player) !void {
    const state = p.getPredictedState(dt);
    try p.handleEvent(Player.Events.SetPos, .{state.cam_pos});
    try p.handleEvent(Player.Events.SetRot, .{state.cam_rot});

    const dpos = Vec4f.new(.{
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
    const drot = Vec4f.new(.{
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

    if (!std.mem.eql(f32, &state.cam_dpos.a, &dpos.a))
        try p.handleEvent(Player.Events.SetDPos, .{dpos});
    if (!std.mem.eql(f32, &state.cam_drot.a, &drot.a))
        try p.handleEvent(Player.Events.SetDRot, .{drot});
}

pub fn drawScene() !void {
    const dt = accum_tick_secs;
    const captured_model_zrot = @mod(model_zrot + model_dzrot * dt, 3.141593 * 2.0);

    gfxstate.shader_uniforms.mproj = Mat4f.perspective(
        @intToFloat(f32, gfx.width),
        @intToFloat(f32, gfx.height),
        0.01,
        1000.0,
    );
    try gl.clearColor(0.2, 0.0, 0.4, 0.0);
    try gl.clear(.{ .color = true, .depth = true });

    {
        const p: Player.State = local_player.?.getPredictedState(dt);
        gfxstate.shader_uniforms.cam_pos = p.cam_pos;
        gfxstate.shader_uniforms.mcam = Mat4f.I
            .rotate(p.cam_rot.a[0], 1.0, 0.0, 0.0)
            .rotate(p.cam_rot.a[1], 0.0, 1.0, 0.0)
            .translate(-p.cam_pos.a[0], -p.cam_pos.a[1], -p.cam_pos.a[2]);
        gfxstate.shader_uniforms.light = p.cam_pos;
    }

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
            gfxstate.shader_uniforms.mmodel = Mat4f.I
                .translate(0.5, 0.0, -3.0)
                .rotate(captured_model_zrot, 0.0, 1.0, 0.0)
                .rotate(captured_model_zrot * 2.0, 0.0, 0.0, 1.0);
            try shadermagic.loadUniforms(&shader_prog, @TypeOf(gfxstate.shader_uniforms), &gfxstate.shader_uniforms, &shader_prog_unicache);
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

            try gfxstate.shader_uniforms.smp0.bindTexture(test_tex);
            try gl.useProgram(textured_prog);
            defer gl.unuseProgram() catch {};
            gfxstate.shader_uniforms.mmodel = Mat4f.I
                .translate(-5.0, -2.0, -10.0); //.rotate(-captured_model_zrot, 0.0, 1.0, 0.0);
            try shadermagic.loadUniforms(&textured_prog, @TypeOf(gfxstate.shader_uniforms), &gfxstate.shader_uniforms, &textured_prog_unicache);
            try model_pyramid.?.draw(.Triangles);
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

            try gfxstate.shader_uniforms.smp0.bindTexture(test_tex);
            try gl.useProgram(textured_prog);
            defer gl.unuseProgram() catch {};
            gfxstate.shader_uniforms.mmodel = Mat4f.I
                .translate(0.0, -2.0, 0.0);
            try shadermagic.loadUniforms(&textured_prog, @TypeOf(gfxstate.shader_uniforms), &gfxstate.shader_uniforms, &textured_prog_unicache);
            try model_floor.draw(.Triangles);
        }

        {
            defer gl.activeTexture(0) catch {};
            try gl.activeTexture(0);
            defer {
                // FIXME: if activeTexture somehow fails, this may unbind the wrong slot --GM
                gl.activeTexture(0) catch {};
                gl.Texture2D.unbindTexture() catch {};
            }
            try gl.Texture2D.bindTexture(font_renderer.font_tex);

            try gfxstate.shader_uniforms.smp0.bindTexture(font_renderer.font_tex);
            try gl.useProgram(font_renderer.bb_font_prog);
            defer gl.unuseProgram() catch {};
            gfxstate.shader_uniforms.font_color = Vec4f.new(.{ 0.5, 0.7, 1.0, 1.0 });
            gfxstate.shader_uniforms.mmodel = Mat4f.I
                .translate(0.0, 0.0, -1.0);
            try shadermagic.loadUniforms(&font_renderer.bb_font_prog, @TypeOf(gfxstate.shader_uniforms), &gfxstate.shader_uniforms, &font_renderer.bb_font_prog_unicache);
            try font_renderer.model_fonttest.?.draw(.Triangles);
        }

        {
            try gl.useProgram(shader_prog);
            defer gl.unuseProgram() catch {};
            var iter = session.?.players.iterator();
            while (iter.next()) |kv| {
                const otherp: Player.State = kv.value_ptr.*.getPredictedState(dt);
                gfxstate.shader_uniforms.mmodel = Mat4f.I
                    .translate(otherp.cam_pos.a[0], otherp.cam_pos.a[1], otherp.cam_pos.a[2])
                    .scale(0.1, 0.1, 0.1)
                    .rotate(-otherp.cam_rot.a[1], 0.0, 1.0, 0.0)
                    .rotate(-otherp.cam_rot.a[0], 1.0, 0.0, 0.0);
                try shadermagic.loadUniforms(&shader_prog, @TypeOf(gfxstate.shader_uniforms), &gfxstate.shader_uniforms, &shader_prog_unicache);
                try model_base.draw(.Triangles);
            }
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
            gfx.setTitle(try std.fmt.bufPrintZ(&buf, "sekaigu pre-alpha | FPS: {}", .{fps_counter}));
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
