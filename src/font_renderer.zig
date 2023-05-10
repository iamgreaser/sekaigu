// SPDX-License-Identifier: AGPL-3.0-or-later
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

pub const model_fonttest_showatlas = Model(VA_P3F_BP3F_T2F_C1F, u16){
    .va = &[_]VA_P3F_BP3F_T2F_C1F{
        .{ .pos = .{ 0.0, 16.0, 0.0 }, .bpos = .{ 0.0, 0.0, 0.0 }, .tex0 = .{ 0.0, 0.0 }, .color = 1.0 },
        .{ .pos = .{ 0.0, 0.0, 0.0 }, .bpos = .{ 0.0, 0.0, 0.0 }, .tex0 = .{ 0.0, 4.0 }, .color = 1.0 },
        .{ .pos = .{ 16.0, 0.0, 0.0 }, .bpos = .{ 0.0, 0.0, 0.0 }, .tex0 = .{ 4.0, 4.0 }, .color = 1.0 },
        .{ .pos = .{ 16.0, 16.0, 0.0 }, .bpos = .{ 0.0, 0.0, 0.0 }, .tex0 = .{ 4.0, 0.0 }, .color = 1.0 },
    },
    .idx_list = &[_]u16{
        0, 1, 2,
        0, 2, 3,
    },
};
pub var model_fonttest: ?Model(VA_P3F_BP3F_T2F_C1F, u16) = null;

const VA_P3F_BP3F_T2F_C1F = struct {
    pos: [3]f32, // origin in 3D space
    bpos: [3]f32, // billboard position offset in metres (3D space) or pixels (2D space)
    tex0: [2]f32, // note: floor(x) selects channel, floor(y) selects bit to use
    color: f32, // black through white
};
const bb_font_src = shadermagic.makeShaderSource(.{
    .uniform_type = @TypeOf(gfxstate.shader_uniforms),
    .attrib_type = VA_P3F_BP3F_T2F_C1F,
    .varyings = &[_]shadermagic.MakeShaderSourceOptions.FieldEntry{
        .{ "vec2", "vtex0" },
        .{ "vec4", "vcolor" },
    },
    .vert = (
        \\void main () {
        \\    vtex0 = itex0.st;
        \\    vcolor = vec4(icolor * font_color.rgb, font_color.a);
        \\    vec4 rwpos = mmodel * ipos;
        \\    vec4 rspos = mcam * rwpos;
        \\    vec4 rpos = mproj * (rspos + vec4(ibpos.xyz, 0.0));
        \\    gl_Position = rpos;
        \\}
    ),
    .frag = (
        \\bool fontbit (vec2 t0) {
        \\    vec2 chn0 = floor(t0);
        \\    vec2 tex0 = vtex0 - chn0;
        \\    vec4 t0sample = texture2D(smp0, tex0);
        \\    float t0maskf = (chn0.x < 2.0
        \\        ? (chn0.x < 1.0 ? t0sample.r : t0sample.g)
        \\        : (chn0.x < 3.0 ? t0sample.b : t0sample.a));
        \\    t0maskf = (t0maskf * 15.0 + 0.5) / 16.0;
        \\    return mod(t0maskf*pow(2.0, chn0.y), 1.0) >= 0.5;
        \\}
        \\
        \\void main () {
        \\    bool t0val = fontbit(vtex0);
        \\    if (!t0val) discard;
        \\    gl_FragColor = (t0val ? vcolor : vec4(0.0, 0.0, 0.0, 1.0));
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
                const xstep: u8 = switch (@truncate(u1, char_idx_and_width)) {
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

    log.info("Generating test string", .{});
    // Use 5cm characters
    model_fonttest = try bakeString(
        allocator,
        0.5,
        0.5,
        0.05,
        "世界具 へ ようこそ! and some English text too... ist das güt? 💩 and Unicode does not need 直し",
    );
    errdefer (model_fonttest orelse unreachable).deinit();

    log.info("Font renderer initialised", .{});
}

// TODO: Set a pivot point --GM
pub fn bakeString(
    allocator: Allocator,
    xpivot: f32,
    ypivot: f32,
    unit_size: f32,
    str: []const u8,
) !Model(VA_P3F_BP3F_T2F_C1F, u16) {
    const view = try std.unicode.Utf8View.init(str);

    // Compute width
    var xlen: usize = 0;
    var ylen: usize = 16;
    var charcount: usize = 0;
    {
        var iter = view.iterator();
        while (iter.nextCodepoint()) |codepoint| {
            const fme = font_map.get(codepoint) orelse font_map.get(0xFFFD) orelse @panic("Font missing Unicode substitution character!");
            //const fme = font_map.get(codepoint) orelse @panic("Font missing character!");
            xlen += fme.xstep;
            charcount += 1;
        }
    }

    var va = try allocator.alloc(VA_P3F_BP3F_T2F_C1F, charcount * 4 * 5);
    errdefer allocator.free(va);
    var idx_list = try allocator.alloc(u16, charcount * 3 * 2 * 5);
    errdefer allocator.free(idx_list);
    var vapos: usize = 0;
    var idxpos: usize = 0;
    var xoffs: f32 = (@intToFloat(f32, xlen) / 16.0 * -xpivot) * unit_size;
    var yoffs: f32 = (@intToFloat(f32, ylen) / 16.0 * ypivot) * unit_size;
    {
        var iter = view.iterator();
        while (iter.nextCodepoint()) |codepoint| {
            const fme = font_map.get(codepoint) orelse font_map.get(0xFFFD) orelse @panic("Font missing Unicode substitution character!");
            const x0: f32 = xoffs + @intToFloat(f32, fme.dstxoffs) / 16.0 * unit_size;
            const y0: f32 = yoffs - @intToFloat(f32, fme.dstyoffs) / 16.0 * unit_size;
            const x1: f32 = x0 + @intToFloat(f32, fme.xsize) / 16.0 * unit_size;
            const y1: f32 = y0 - @intToFloat(f32, fme.ysize) / 16.0 * unit_size;
            const tx0: f32 = (1.0 / 1024.0) * @intToFloat(f32, fme.srcxoffs);
            const ty0: f32 = (1.0 / 1024.0) * @intToFloat(f32, fme.srcyoffs);
            const tx1: f32 = tx0 + (1.0 / 1024.0) * @intToFloat(f32, fme.xsize);
            const ty1: f32 = ty0 + (1.0 / 1024.0) * @intToFloat(f32, fme.ysize);
            //const tx0: f32 = 0.0;
            //const ty0: f32 = 0.0;
            //const tx1: f32 = 0.0;
            //const ty1: f32 = 0.0;
            const halfoffs = unit_size / 16.0 / 2.0;
            const zoffs = 0.001;
            const offstab = [_][4]f32{
                .{ 0.0, 0.0, 0.0, 1.0 },
                .{ -halfoffs, 0.0, -zoffs, 0.0 },
                .{ 0.0, -halfoffs, -zoffs, 0.0 },
                .{ halfoffs, 0.0, -zoffs, 0.0 },
                .{ 0.0, halfoffs, -zoffs, 0.0 },
            };
            for (offstab) |o| {
                const ox = o[0];
                const oy = o[1];
                const oz = o[2];
                const oc = o[3];
                va[vapos + 0] = VA_P3F_BP3F_T2F_C1F{ .pos = .{ 0.0, 0.0, 0.0 }, .bpos = .{ x0 + ox, y0 + oy, oz }, .tex0 = .{ tx0, ty0 }, .color = oc };
                va[vapos + 1] = VA_P3F_BP3F_T2F_C1F{ .pos = .{ 0.0, 0.0, 0.0 }, .bpos = .{ x0 + ox, y1 + oy, oz }, .tex0 = .{ tx0, ty1 }, .color = oc };
                va[vapos + 2] = VA_P3F_BP3F_T2F_C1F{ .pos = .{ 0.0, 0.0, 0.0 }, .bpos = .{ x1 + ox, y1 + oy, oz }, .tex0 = .{ tx1, ty1 }, .color = oc };
                va[vapos + 3] = VA_P3F_BP3F_T2F_C1F{ .pos = .{ 0.0, 0.0, 0.0 }, .bpos = .{ x1 + ox, y0 + oy, oz }, .tex0 = .{ tx1, ty0 }, .color = oc };
                idx_list[idxpos + 0] = @intCast(u16, vapos + 0);
                idx_list[idxpos + 1] = @intCast(u16, vapos + 1);
                idx_list[idxpos + 2] = @intCast(u16, vapos + 2);
                idx_list[idxpos + 3] = @intCast(u16, vapos + 0);
                idx_list[idxpos + 4] = @intCast(u16, vapos + 2);
                idx_list[idxpos + 5] = @intCast(u16, vapos + 3);
                vapos += 4;
                idxpos += 6;
            }
            // Advance
            xoffs += @intToFloat(f32, fme.xstep) / 16.0 * unit_size;
        }
    }
    var result = Model(VA_P3F_BP3F_T2F_C1F, u16){
        .va = va,
        .idx_list = idx_list,
        .allocator = allocator,
        .va_owned = va,
        .idx_list_owned = idx_list,
    };
    errdefer result.deinit();
    try result.load();

    return result;
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
