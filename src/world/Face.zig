const linalg = @import("../linalg.zig");
const Vec2f = linalg.Vec2f;
const Vec3f = linalg.Vec3f;
const Vec4f = linalg.Vec4f;
const Mat2f = linalg.Mat2f;
const Mat3f = linalg.Mat3f;
const Mat4f = linalg.Mat4f;
const IdxType = @import("IdxType.zig").IdxType;

pub fn Face(comptime Parent: type, comptime parent_field: []const u8) type {
    return struct {
        const Self = @This();
        pub const Idx = IdxType(Parent, parent_field, Self);
        norm: Vec3f,
        offs: f32,

        pub fn calcSignedDist(self: *const Self, point: Vec3f) f32 {
            return self.norm.dot(point) + self.offs;
        }

        pub fn project(self: *const Self, point: Vec3f) Vec3f {
            return point.sub(self.norm.mul(self.calcSignedDist(point)));
        }

        pub fn raycast(self: *const Self, refpos: Vec3f, dir: Vec3f) !f32 {
            const EPSILON = 0.0001;
            const tangentdist = self.calcSignedDist(
                refpos,
            );
            const dirdot = dir.dot(self.norm);
            if (@fabs(dirdot) < EPSILON) {
                return error.NoIntersection;
            }
            const realdist = -tangentdist / dirdot;
            return realdist;
        }

        pub fn projectRay(self: *const Self, refpos: Vec3f, dir: Vec3f) !Vec3f {
            return refpos.add(dir.mul(try self.raycast(refpos, dir)));
        }

        pub fn projectDir(self: *const Self, point: Vec3f) Vec3f {
            return point.sub(self.norm.mul(self.norm.dot(point)));
        }
    };
}
