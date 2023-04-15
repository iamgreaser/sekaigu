const linalg = @import("../linalg.zig");
const Vec2f = linalg.Vec2f;
const Vec3f = linalg.Vec3f;
const Vec4f = linalg.Vec4f;
const Mat2f = linalg.Mat2f;
const Mat3f = linalg.Mat3f;
const Mat4f = linalg.Mat4f;
const IdxType = @import("IdxType.zig").IdxType;

pub fn Edge(comptime Parent: type, comptime parent_field: []const u8, comptime Face: type, comptime Point: type) type {
    return struct {
        const Self = @This();
        pub const Idx = IdxType(Parent, parent_field, Self);
        refpoint: Vec3f,
        dir: Vec3f,
        face0: Face.Idx,
        face1: Face.Idx,
        limitneg: ?f32 = null,
        limitpos: ?f32 = null,
        limitnegpoint: ?Point.Idx = null,
        limitpospoint: ?Point.Idx = null,

        pub fn getNegPoint(self: *const Self) ?Vec3f {
            return if (self.limitneg) |lim| self.refpoint.add(self.dir.mul(lim)) else null;
        }

        pub fn getPosPoint(self: *const Self) ?Vec3f {
            return if (self.limitpos) |lim| self.refpoint.add(self.dir.mul(lim)) else null;
        }
    };
}
