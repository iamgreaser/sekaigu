const std = @import("std");
const log = std.log.scoped(.gl_Program);
const C = @import("../c.zig");
const gl = @import("../gl.zig");
const _TestError = gl._TestError;

handle: C.GLuint,
const Self = @This();
pub const Dummy = Self{ .handle = 0 };
