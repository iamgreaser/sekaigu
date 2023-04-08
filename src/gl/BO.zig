const builtin = @import("builtin");
const std = @import("std");
const log = std.log.scoped(.gl_Program);
const C = @import("../c.zig");
const gl = @import("../gl.zig");
const _TestError = gl._TestError;

handle: C.GLuint,
const Self = @This();
pub const Dummy = Self{ .handle = 0 };

pub fn genBuffer() !Self {
    var result: C.GLuint = 0;
    if (comptime builtin.target.isWasm()) {
        result = C.glCreateBuffer();
    } else {
        C.glGenBuffers(1, &result);
    }
    try _TestError();
    return Self{ .handle = result };
}
