const linalg = @import("../linalg.zig");
const Vec2f = linalg.Vec2f;
const Vec3f = linalg.Vec3f;
const Vec4f = linalg.Vec4f;
const Mat2f = linalg.Mat2f;
const Mat3f = linalg.Mat3f;
const Mat4f = linalg.Mat4f;
const IdxType = @import("../IdxType.zig").IdxType;

pub fn Point(comptime Parent: type, comptime parent_field: []const u8) type {
    return struct {
        const Self = @This();
        pub const Idx = IdxType(Parent, parent_field, Self);
        pos: Vec3f,
    };
}
