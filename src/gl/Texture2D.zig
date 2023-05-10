// SPDX-License-Identifier: AGPL-3.0-or-later
const builtin = @import("builtin");
const std = @import("std");
const log = std.log.scoped(.gl_Program);
const C = @import("../c.zig");
const gl = @import("../gl.zig");
const _TestError = gl._TestError;

handle: C.GLuint,
sampler: C.GLuint = 0,
const Self = @This();
pub const TARGET = C.GL_TEXTURE_2D;
pub const Dummy = Self{ .handle = 0 };

pub fn genTexture() !Self {
    var handles: [1]C.GLuint = .{0};
    if (comptime builtin.target.isWasm()) {
        handles[0] = C.glCreateTexture();
    } else {
        C.glGenTextures(1, &handles);
    }
    try _TestError();
    return Self{ .handle = handles[0] };
}

pub fn bindTexture(texture: Self) !void {
    if (texture.handle == 0) return error.DummyNotAllocated;
    C.glBindTexture(TARGET, texture.handle);
    try _TestError();
}

pub fn unbindTexture() !void {
    C.glBindTexture(TARGET, 0);
    try _TestError();
}

pub const TextureFormat = enum(u16) {
    RGBA8888,
    RGB888,
    RGBA4444,
    RGBA5551,
    RGB565,
    LA88,
    L8,
    A8,
};
fn _dataTypeForFormat(comptime format: TextureFormat) type {
    const basetype: type = switch (format) {
        .RGBA8888 => u32,
        .RGB888 => [3]u8,
        .RGBA4444, .RGBA5551, .RGB565, .LA88 => u16,
        .L8, .A8 => u8,
    };
    return []const basetype;
}
pub fn texImage2D(
    level: u8,
    width: usize,
    height: usize,
    comptime format: TextureFormat,
    data: _dataTypeForFormat(format),
) !void {
    const glformat: C.GLenum = switch (format) {
        .A8 => C.GL_ALPHA,
        .L8 => C.GL_LUMINANCE,
        .LA88 => C.GL_LUMINANCE_ALPHA,
        .RGB888, .RGB565 => C.GL_RGB,
        .RGBA8888, .RGBA4444, .RGBA5551 => C.GL_RGBA,
    };
    const glsize: C.GLenum = switch (format) {
        .RGBA8888, .RGB888, .LA88, .L8, .A8 => C.GL_UNSIGNED_BYTE,
        .RGBA4444 => C.GL_UNSIGNED_SHORT_4_4_4_4,
        .RGBA5551 => C.GL_UNSIGNED_SHORT_5_5_5_1,
        .RGB565 => C.GL_UNSIGNED_SHORT_5_6_5,
    };
    if (data.len < width * height) {
        return error.BufferOverflow;
    }

    if (comptime builtin.target.isWasm()) {
        C.glTexImage2D(
            TARGET,
            level,
            glformat,
            @intCast(C.GLsizei, width),
            @intCast(C.GLsizei, height),
            0, // Border must be 0
            glformat,
            glsize,
            &data[0],
            @intCast(C.GLsizei, @sizeOf(@TypeOf(data[0])) * data.len),
        );
    } else {
        C.glTexImage2D(
            TARGET,
            level,
            glformat,
            @intCast(C.GLsizei, width),
            @intCast(C.GLsizei, height),
            0, // Border must be 0
            glformat,
            glsize,
            &data[0],
        );
    }
    try _TestError();
}

pub fn generateMipmap() !void {
    C.glGenerateMipmap(TARGET);
    try _TestError();
}
