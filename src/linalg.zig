const std = @import("std");
const log = std.log.scoped(.linalg);

pub fn Vec(comptime N: usize, comptime T: type) type {
    return struct {
        const Self = @This();
        a: [N]T,

        pub fn new(data: [N]T) Self {
            return Self{ .a = data };
        }
    };
}

pub fn Mat(comptime N: usize, comptime T: type) type {
    return struct {
        const Self = @This();
        a: [N * N]T,

        fn buildIdentity() Self {
            var result = Self{ .a = undefined };
            for (result.a, 0..) |v, i| {
                _ = v;
                const r = i % N;
                const c = i / N;
                result.a[i] = if (r == c) 1.0 else 0.0;
            }
            return result;
        }
        pub const I = buildIdentity();
    };
}

pub const Vec2f = Vec(2, f32);
pub const Vec3f = Vec(3, f32);
pub const Vec4f = Vec(4, f32);
pub const Mat2f = Mat(2, f32);
pub const Mat3f = Mat(3, f32);
pub const Mat4f = Mat(4, f32);
