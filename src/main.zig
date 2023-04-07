const std = @import("std");
const log = std.log.scoped(.main);
const time = std.time;
const C = @import("c.zig");

const GfxContext = @import("GfxContext.zig");
const gl = @import("gl.zig");
const shadermagic = @import("shadermagic.zig");
const linalg = @import("linalg.zig");
const Vec2f = linalg.Vec2f;
const Vec3f = linalg.Vec3f;
const Vec4f = linalg.Vec4f;
const Mat2f = linalg.Mat2f;
const Mat3f = linalg.Mat3f;
const Mat4f = linalg.Mat4f;

const MAX_FPS = 60;
const NSEC_PER_FRAME = @divFloor(time.ns_per_s, MAX_FPS);

pub const VA_P3F_C3U8_N3I8 = struct {
    pos: [3]f32,
    color: [3]u8,
    normal: [3]i8,
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

var model_base = Model(VA_P3F_C3U8_N3I8, u16){
    .va = &[_]VA_P3F_C3U8_N3I8{
        // Z- Rear
        .{ .pos = .{ -1.0, -1.0, -1.0 }, .color = .{ 0x80, 0x80, 0x80 }, .normal = .{ 0, 0, -128 } },
        .{ .pos = .{ -1.0, 1.0, -1.0 }, .color = .{ 0x80, 0xFF, 0x80 }, .normal = .{ 0, 0, -128 } },
        .{ .pos = .{ 1.0, -1.0, -1.0 }, .color = .{ 0xFF, 0x80, 0x80 }, .normal = .{ 0, 0, -128 } },
        .{ .pos = .{ 1.0, 1.0, -1.0 }, .color = .{ 0xFF, 0xFF, 0x80 }, .normal = .{ 0, 0, -128 } },
        // Z+ Front
        .{ .pos = .{ -1.0, -1.0, 1.0 }, .color = .{ 0x80, 0x80, 0xFF }, .normal = .{ 0, 0, 127 } },
        .{ .pos = .{ 1.0, -1.0, 1.0 }, .color = .{ 0xFF, 0x80, 0xFF }, .normal = .{ 0, 0, 127 } },
        .{ .pos = .{ -1.0, 1.0, 1.0 }, .color = .{ 0x80, 0xFF, 0xFF }, .normal = .{ 0, 0, 127 } },
        .{ .pos = .{ 1.0, 1.0, 1.0 }, .color = .{ 0xFF, 0xFF, 0xFF }, .normal = .{ 0, 0, 127 } },
        // X-
        .{ .pos = .{ -1.0, -1.0, -1.0 }, .color = .{ 0x80, 0x80, 0x80 }, .normal = .{ -128, 0, 0 } },
        .{ .pos = .{ -1.0, -1.0, 1.0 }, .color = .{ 0x80, 0x80, 0xFF }, .normal = .{ -128, 0, 0 } },
        .{ .pos = .{ -1.0, 1.0, -1.0 }, .color = .{ 0x80, 0xFF, 0x80 }, .normal = .{ -128, 0, 0 } },
        .{ .pos = .{ -1.0, 1.0, 1.0 }, .color = .{ 0x80, 0xFF, 0xFF }, .normal = .{ -128, 0, 0 } },
        // X+
        .{ .pos = .{ 1.0, -1.0, -1.0 }, .color = .{ 0xFF, 0x80, 0x80 }, .normal = .{ 127, 0, 0 } },
        .{ .pos = .{ 1.0, 1.0, -1.0 }, .color = .{ 0xFF, 0xFF, 0x80 }, .normal = .{ 127, 0, 0 } },
        .{ .pos = .{ 1.0, -1.0, 1.0 }, .color = .{ 0xFF, 0x80, 0xFF }, .normal = .{ 127, 0, 0 } },
        .{ .pos = .{ 1.0, 1.0, 1.0 }, .color = .{ 0xFF, 0xFF, 0xFF }, .normal = .{ 127, 0, 0 } },
        // Y-
        .{ .pos = .{ -1.0, -1.0, -1.0 }, .color = .{ 0x80, 0x80, 0x80 }, .normal = .{ 0, -128, 0 } },
        .{ .pos = .{ 1.0, -1.0, -1.0 }, .color = .{ 0xFF, 0x80, 0x80 }, .normal = .{ 0, -128, 0 } },
        .{ .pos = .{ -1.0, -1.0, 1.0 }, .color = .{ 0x80, 0x80, 0xFF }, .normal = .{ 0, -128, 0 } },
        .{ .pos = .{ 1.0, -1.0, 1.0 }, .color = .{ 0xFF, 0x80, 0xFF }, .normal = .{ 0, -128, 0 } },
        // Y+
        .{ .pos = .{ -1.0, 1.0, -1.0 }, .color = .{ 0x80, 0xFF, 0x80 }, .normal = .{ 0, 127, 0 } },
        .{ .pos = .{ -1.0, 1.0, 1.0 }, .color = .{ 0x80, 0xFF, 0xFF }, .normal = .{ 0, 127, 0 } },
        .{ .pos = .{ 1.0, 1.0, -1.0 }, .color = .{ 0xFF, 0xFF, 0x80 }, .normal = .{ 0, 127, 0 } },
        .{ .pos = .{ 1.0, 1.0, 1.0 }, .color = .{ 0xFF, 0xFF, 0xFF }, .normal = .{ 0, 127, 0 } },
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
    light: Vec4f = Vec4f.new(.{ 0.0, 2.0, 0.0, 1.0 }),
} = .{};
const shader_src = shadermagic.makeShaderSource(.{
    .uniform_type = @TypeOf(shader_uniforms),
    .attrib_type = VA_P3F_C3U8_N3I8,
    .varyings = &[_]shadermagic.MakeShaderSourceOptions.FieldEntry{
        .{ "vec4", "vcolor" },
        .{ "vec3", "vwpos" },
        .{ "vec3", "vspos" },
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
        \\    vec4 rspos = mcam * rwpos;
        \\    vec4 rpos = mproj * rspos;
        \\    vec4 rnormal = vec4(normalize(vec3zeroclamp(inormal.xyz)), 0.0);
        \\    vwpos = rwpos.xyz;
        \\    vspos = rspos.xyz;
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
        \\    vec3 normal = normalize(vnormal);
        \\    vec3 vlightdir = normalize(light.xyz - vwpos);
        \\    vec3 ambdiff = Ma + Md*max(0.0, dot(vlightdir, normal));
        \\    vec3 vcamdir = -normalize(vspos);
        \\    vec3 vspecdir = 2.0*normal*dot(normal, vlightdir) - vlightdir;
        \\    vec3 spec = Ms*pow(max(0.0, dot(vcamdir, vspecdir)), MsExp);
        \\    gl_FragColor = vec4((vcolor.rgb*ambdiff)+spec, vcolor.a);
        \\}
    ),
});
var shader_prog: gl.Program = gl.Program.Dummy;

pub fn main() !void {
    var gfx = try GfxContext.new();
    try gfx.init();
    defer gfx.free();

    // Compile the shader
    shader_prog = try shader_src.compileProgram();

    // Load the VBOs
    try model_base.load();

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

    var timer = try time.Timer.start();
    var time_accum: u64 = 0;
    var frame_time_accum: i64 = 0;
    var fps_time_accum: u64 = 0;
    var fps_counter: u64 = 0;
    var dt: f32 = 0.0;
    done: while (true) {
        fps_counter += 1;
        try gl.clearColor(0.2, 0.0, 0.4, 0.0);
        try gl.clear(.{ .color = true, .depth = true });
        shader_uniforms.mmodel = Mat4f.I
            .translate(0.5, 0.0, -3.0)
            .rotate(model_zrot, 0.0, 1.0, 0.0)
            .rotate(model_zrot * 2.0, 0.0, 0.0, 1.0);
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

            try gl.useProgram(shader_prog);
            defer gl.unuseProgram() catch {};
            try shadermagic.loadUniforms(shader_prog, @TypeOf(shader_uniforms), &shader_uniforms);

            try model_base.draw(.Triangles);
        }

        gfx.flip();
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
        var ev: C.SDL_Event = undefined;
        while (C.SDL_PollEvent(&ev) != 0) {
            switch (ev.type) {
                C.SDL_QUIT => {
                    break :done;
                },
                C.SDL_KEYDOWN, C.SDL_KEYUP => {
                    const pressed = (ev.type == C.SDL_KEYDOWN);
                    const code = ev.key.keysym.sym;
                    gotkey: inline for (@typeInfo(@TypeOf(keys)).Struct.fields) |field| {
                        if (code == @field(C, "SDLK_" ++ field.name)) {
                            @field(keys, field.name) = pressed;
                            break :gotkey;
                        }
                    }
                    //log.debug("key {s} {}", .{ if (pressed) "1" else "0", ev.key.keysym.sym });

                },
                else => {},
            }
        }
        frame_time_accum += NSEC_PER_FRAME;
        const sleep_time = frame_time_accum - @intCast(i64, timer.read());
        if (sleep_time > 0) {
            time.sleep(@intCast(u64, sleep_time));
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
        dt = @floatCast(f32, @intToFloat(f64, dt_snap) / @intToFloat(f64, time.ns_per_s * 1));
    }
}
