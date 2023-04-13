const std = @import("std");
const log = std.log.scoped(.font_renderer);
const Allocator = std.mem.Allocator;

const C = @import("c.zig");
const gl = @import("gl.zig");
const shadermagic = @import("shadermagic.zig");
const gfxstate = @import("gfxstate.zig");
const Model = gfxstate.Model;

// TODO: Extract this from the wasm blob for builds with a wasm blob embedded into them --GM
const font_raw_bin = @embedFile("font_raw_bin");
const font_map_bin = @embedFile("font_map_bin");

const FontGlyphInfo = struct {
    srcxoffs: u16,
    srcyoffs: u16,
    dstxoffs: u8,
    dstyoffs: u8,
    xsize: u8,
    ysize: u8,
    xstep: u8,
};
var font_map: std.AutoHashMap(u24, FontGlyphInfo) = undefined;

pub var model_fonttest = Model(VA_P3F_BP2F_T2F, u16){
    .va = &[_]VA_P3F_BP2F_T2F{
        .{ .pos = .{ 0.0, 16.0, 0.0 }, .bpos = .{ 0.0, 0.0 }, .tex0 = .{ 0.0, 0.0 } },
        .{ .pos = .{ 0.0, 0.0, 0.0 }, .bpos = .{ 0.0, 0.0 }, .tex0 = .{ 0.0, 4.0 } },
        .{ .pos = .{ 16.0, 0.0, 0.0 }, .bpos = .{ 0.0, 0.0 }, .tex0 = .{ 4.0, 4.0 } },
        .{ .pos = .{ 16.0, 16.0, 0.0 }, .bpos = .{ 0.0, 0.0 }, .tex0 = .{ 4.0, 0.0 } },
    },
    .idx_list = &[_]u16{
        0, 1, 2,
        0, 2, 3,
    },
};

const VA_P3F_BP2F_T2F = struct {
    pos: [3]f32, // origin in 3D space
    bpos: [2]f32, // billboard position offset in metres (3D space) or pixels (2D space)
    tex0: [2]f32, // note: floor(x) selects channel, floor(y) selects bit to use
};
const bb_font_src = shadermagic.makeShaderSource(.{
    .uniform_type = @TypeOf(gfxstate.shader_uniforms),
    .attrib_type = VA_P3F_BP2F_T2F,
    .varyings = &[_]shadermagic.MakeShaderSourceOptions.FieldEntry{
        .{ "vec2", "vtex0" },
    },
    .vert = (
        \\void main () {
        \\    vtex0 = itex0.st;
        \\    vec4 rwpos = mmodel * ipos;
        \\    vec4 rspos = mcam * rwpos;
        \\    vec4 rpos = mproj * (rspos + vec4(ibpos.xy, 0.0, 0.0));
        \\    gl_Position = rpos;
        \\}
    ),
    .frag = (
        \\void main () {
        \\    vec2 chn0 = floor(vtex0);
        \\    vec2 tex0 = vtex0 - chn0;
        \\    vec4 t0sample = texture2D(smp0, tex0);// - 0.5/1024.0);
        \\    float t0maskf = (chn0.x < 2.0
        \\        ? (chn0.x < 1.0 ? t0sample.r : t0sample.g)
        \\        : (chn0.x < 3.0 ? t0sample.b : t0sample.a));
        \\    t0maskf = (t0maskf * 15.0 + 0.5) / 16.0;
        \\    bool t0val = mod(t0maskf*pow(2.0, chn0.y), 1.0) >= 0.5;
        \\    //bool t0val = fract(t0maskf) >= 0.5;
        \\    if (!t0val) discard;
        \\    gl_FragColor = (t0val ? font_color : vec4(0.0, 0.0, 0.0, 1.0));
        \\}
    ),
});
pub var bb_font_prog: gl.Program = gl.Program.Dummy;
pub var bb_font_prog_unicache: shadermagic.UniformIdxCache(@TypeOf(gfxstate.shader_uniforms)) = .{};
pub var font_tex: gl.Texture2D = gl.Texture2D.Dummy;

var provided_allocator: Allocator = undefined;

pub fn init(allocator: Allocator) !void {
    provided_allocator = allocator;
    log.info("Loading font texture", .{});
    font_tex = try gl.Texture2D.genTexture();
    {
        const SIZE = 1024;
        var buf = try allocator.alloc(u16, SIZE * SIZE);
        defer allocator.free(buf);
        {
            var bytebuf = try allocator.alloc(u8, 2 * SIZE * SIZE);
            defer allocator.free(bytebuf);
            var buf_stream = std.io.fixedBufferStream(font_raw_bin);
            var buf_reader = buf_stream.reader();
            var decompressor = try std.compress.deflate.decompressor(allocator, buf_reader, null);
            defer decompressor.deinit();
            var decompressor_reader = decompressor.reader();
            try decompressor_reader.readNoEof(bytebuf);
            for (buf, 0..) |*v, i| {
                v.* = (@intCast(u16, bytebuf[2 * i + 0])) | (@intCast(u16, bytebuf[2 * i + 1]) << 8);
            }
        }
        log.info("Texture decompressed, now upload", .{});

        defer gl.activeTexture(0) catch {};
        try gl.activeTexture(0);
        defer {
            // FIXME: if activeTexture somehow fails, this may unbind the wrong slot --GM
            gl.activeTexture(0) catch {};
            gl.Texture2D.unbindTexture() catch {};
        }
        try gl.Texture2D.bindTexture(font_tex);
        // TODO: Add bindings for texture parameters --GM
        C.glTexParameteri(C.GL_TEXTURE_2D, C.GL_TEXTURE_WRAP_S, C.GL_REPEAT);
        C.glTexParameteri(C.GL_TEXTURE_2D, C.GL_TEXTURE_WRAP_T, C.GL_REPEAT);
        C.glTexParameteri(C.GL_TEXTURE_2D, C.GL_TEXTURE_MAG_FILTER, C.GL_NEAREST);
        C.glTexParameteri(C.GL_TEXTURE_2D, C.GL_TEXTURE_MIN_FILTER, C.GL_NEAREST);
        try gl._TestError();
        try gl.Texture2D.texImage2D(0, SIZE, SIZE, .RGBA4444, buf);
    }

    log.info("Unpacking font map", .{});
    {
        var buf_stream = std.io.fixedBufferStream(font_map_bin);
        var buf_reader = buf_stream.reader();
        var decompressor = try std.compress.deflate.decompressor(allocator, buf_reader, null);
        defer decompressor.deinit();
        var reader = decompressor.reader();
        const n_empties_8 = try reader.readIntLittle(u24);
        const n_empties_16 = try reader.readIntLittle(u24);
        const n_full_glyphs = try reader.readIntLittle(u24);
        font_map = @TypeOf(font_map).init(allocator);
        errdefer font_map.deinit();
        {
            var prev_char_idx: u24 = 0;
            for (0..n_empties_8) |_| {
                const char_idx: u24 = try readCharDelta24(@TypeOf(reader), &reader, &prev_char_idx);
                try font_map.putNoClobber(char_idx, FontGlyphInfo{
                    .srcxoffs = 0,
                    .srcyoffs = 0,
                    .dstxoffs = 0,
                    .dstyoffs = 0,
                    .xsize = 0,
                    .ysize = 0,
                    .xstep = 8,
                });
            }
        }
        {
            var prev_char_idx: u24 = 0;
            for (0..n_empties_16) |_| {
                const char_idx: u24 = try readCharDelta24(@TypeOf(reader), &reader, &prev_char_idx);
                try font_map.putNoClobber(char_idx, FontGlyphInfo{
                    .srcxoffs = 0,
                    .srcyoffs = 0,
                    .dstxoffs = 0,
                    .dstyoffs = 0,
                    .xsize = 0,
                    .ysize = 0,
                    .xstep = 8,
                });
            }
        }
        {
            var prev_char_idx: u24 = 0;
            var prevsrcx: u16 = 0;
            var prevsrcy: u16 = 0;
            for (0..n_full_glyphs) |_| {
                const char_idx_and_width: u24 = try readCharDelta24(@TypeOf(reader), &reader, &prev_char_idx);
                const char_idx: u24 = char_idx_and_width >> 1;
                const xstep: u8 = switch (@truncate(u1, char_idx)) {
                    0 => @as(u8, 8),
                    1 => @as(u8, 16),
                };
                prevsrcx +%= try reader.readIntLittle(u16);
                const srcxoffs = prevsrcx;
                prevsrcy +%= try reader.readIntLittle(u16);
                const srcyoffs = prevsrcy;
                const pdstoffs = try reader.readIntLittle(u8);
                const dstxoffs = pdstoffs & 0xF;
                const dstyoffs = pdstoffs >> 4;
                const psize = try reader.readIntLittle(u8);
                const xsize = (psize & 0xF) + 1;
                const ysize = (psize >> 4) + 1;
                try font_map.putNoClobber(char_idx, FontGlyphInfo{
                    .srcxoffs = srcxoffs,
                    .srcyoffs = srcyoffs,
                    .dstxoffs = dstxoffs,
                    .dstyoffs = dstyoffs,
                    .xsize = xsize,
                    .ysize = ysize,
                    .xstep = xstep,
                });
            }
        }
    }

    log.info("Compiling font shaders", .{});
    bb_font_prog = try bb_font_src.compileProgram();

    log.info("Font renderer initialised", .{});
}

// Reads a 24-bit encoded delta value
// NOTE: Expects some kind of reader.
fn readCharDelta24(comptime Reader: type, reader: *Reader, prev_ptr: *u24) !u24 {
    const dbyte = try reader.readIntLittle(u8);
    const delta: u24 = if (dbyte == 0x00)
        try reader.readIntLittle(u24) + 0xFF
    else
        @intCast(u24, dbyte) - 1;

    prev_ptr.* += delta;
    return prev_ptr.*;
}

pub fn free() void {
    font_map.deinit();
    // TODO: Delete textures --GM
    // TODO: Delete shaders --GM
}
