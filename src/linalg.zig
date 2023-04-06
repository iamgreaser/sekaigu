const std = @import("std");
const log = std.log.scoped(.linalg);

fn Vec(comptime N: usize, comptime T: type) type {
    return struct {
        const Self = @This();
        a: [N]T,

        pub fn new(data: [N]T) Self {
            return Self{ .a = data };
        }
    };
}

fn Mat(comptime N: usize, comptime T: type) type {
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

pub const Mat4f = struct {
    // NOTE: ALL MATRICES APPEAR TRANSPOSED
    const Self = @This();
    const N = 4;
    const T = f32;
    a: [N * N]T,

    fn buildIdentity() Self {
        var result = Self{ .a = undefined };
        for (0..N * N) |i| {
            const r = i % N;
            const c = i / N;
            result.a[i] = if (r == c) 1.0 else 0.0;
        }
        return result;
    }
    pub const I = buildIdentity();

    pub fn mul(self: Self, other: Self) Self {
        var result = Self{ .a = undefined };
        for (0..N) |i| {
            for (0..N) |j| {
                var total: T = 0.0;
                for (0..N) |k| {
                    total += self.a[(k * N) + j] * other.a[(i * N) + k];
                }
                result.a[(i * N) + j] = total;
            }
        }
        return result;
    }

    pub fn add(self: Self, other: Self) Self {
        var result = Self{ .a = undefined };
        for (0..N * N) |i| {
            result.a[i] = self.a[i] + other.a[i];
        }
        return result;
    }

    pub fn sub(self: Self, other: Self) Self {
        var result = Self{ .a = undefined };
        for (0..N * N) |i| {
            result.a[i] = self.a[i] - other.a[i];
        }
        return result;
    }

    pub fn mulScalar(self: Self, other: T) Self {
        var result = Self{ .a = undefined };
        for (0..N * N) |i| {
            result.a[i] = self.a[i] * other;
        }
        return result;
    }

    pub fn genScale(x: T, y: T, z: T) Self {
        return Self{
            .a = [N * N]T{
                x,   0.0, 0.0, 0.0,
                0.0, y,   0.0, 0.0,
                0.0, 0.0, z,   0.0,
                0.0, 0.0, 0.0, 1.0,
            },
        };
    }
    pub fn scale(self: Self, x: T, y: T, z: T) Self {
        return self.mul(genScale(x, y, z));
    }

    pub fn genTranslate(x: T, y: T, z: T) Self {
        return Self{
            .a = [N * N]T{
                1.0, 0.0, 0.0, 0.0,
                0.0, 1.0, 0.0, 0.0,
                0.0, 0.0, 1.0, 0.0,
                x,   y,   z,   1.0,
            },
        };
    }
    pub fn translate(self: Self, x: T, y: T, z: T) Self {
        return self.mul(genTranslate(x, y, z));
    }

    pub fn genRotate(ang: T, x: T, y: T, z: T) Self {
        const invlen = 1.0 / @max(0.0001, @sqrt((x * x) + (y * y) + (z * z)));
        const xn = x * invlen;
        const yn = y * invlen;
        const zn = z * invlen;
        const rc = @cos(ang);
        const rs = @sin(ang);

        // W,W term
        const mw = Self{
            .a = [N * N]T{
                0.0, 0.0, 0.0, 0.0,
                0.0, 0.0, 0.0, 0.0,
                0.0, 0.0, 0.0, 0.0,
                0.0, 0.0, 0.0, 1.0,
            },
        };

        // base term
        const mb = Self{
            .a = [N * N]T{
                xn * xn, xn * yn, xn * zn, 0.0,
                yn * xn, yn * yn, yn * zn, 0.0,
                zn * xn, zn * yn, zn * zn, 0.0,
                0.0,     0.0,     0.0,     0.0,
            },
        };

        // cos term
        const mc = (Self.I.sub(mw).sub(mb)).mulScalar(rc);

        // sin term
        const ms = (Self{
            .a = [N * N]T{
                0.0, zn,  -yn, 0.0,
                -zn, 0.0, xn,  0.0,
                yn,  -xn, 0.0, 0.0,
                0.0, 0.0, 0.0, 0.0,
            },
        }).mulScalar(rs);

        return mb.add(mc).add(ms).add(mw);
    }
    pub fn rotate(self: Self, ang: T, x: T, y: T, z: T) Self {
        return self.mul(genRotate(ang, x, y, z));
    }

    pub fn projection(width: T, height: T, znear: T, zfar: T) Self {
        // TODO! --GM
        return (Self{
            .a = [N * N]T{
                1.0, 0.0, 0.0,                                    0.0,
                0.0, 1.0, 0.0,                                    0.0,
                0.0, 0.0, -(zfar + znear) / (zfar - znear),       -1.0,
                0.0, 0.0, -(2.0 * zfar * znear) / (zfar - znear), 0.0,
            },
        }).scale(
            if (width < height) 1.0 else height / width,
            if (width < height) width / height else 1.0,
            1.0,
        );
    }
};

pub const Vec2f = Vec(2, f32);
pub const Vec3f = Vec(3, f32);
pub const Vec4f = Vec(4, f32);
pub const Mat2f = Mat(2, f32);
pub const Mat3f = Mat(3, f32);
//pub const Mat4f = Mat(4, f32);
