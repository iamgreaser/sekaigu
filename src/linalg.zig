const std = @import("std");
const log = std.log.scoped(.linalg);

pub fn Vec(comptime N: usize, comptime T: type) type {
    return struct {
        const Self = @This();
        pub const SCHEMA = .{"a"};
        a: [N]T,

        pub fn new(data: [N]T) Self {
            return Self{ .a = data };
        }

        fn buildIdentity() Self {
            var result = Self{ .a = undefined };
            for (result.a, 0..) |v, i| {
                _ = v;
                result.a[i] = 0.0;
            }
            return result;
        }
        pub const I = buildIdentity();

        pub fn add(self: Self, other: Self) Self {
            var result = Self{ .a = undefined };
            for (0..N) |i| {
                result.a[i] = self.a[i] + other.a[i];
            }
            return result;
        }

        pub fn sub(self: Self, other: Self) Self {
            var result = Self{ .a = undefined };
            for (0..N) |i| {
                result.a[i] = self.a[i] - other.a[i];
            }
            return result;
        }

        pub fn mul(self: Self, other: anytype) Self {
            switch (@TypeOf(other)) {
                f32, f64, comptime_float => {
                    var result = Self{ .a = undefined };
                    for (0..N) |i| {
                        result.a[i] = self.a[i] * other;
                    }
                    return result;
                },
                else => @compileError("unhandled type for vec mul"),
            }
        }

        pub fn dot(self: Self, other: Self) T {
            var result: T = 0.0;
            for (0..N) |i| {
                result += self.a[i] * other.a[i];
            }
            return result;
        }

        pub fn length2(self: Self) T {
            return self.dot(self);
        }

        pub fn length(self: Self) T {
            return @sqrt(self.length2());
        }

        pub fn normalize(self: Self) Self {
            return self.mul(1.0 / @max(0.00001, self.length()));
        }

        pub fn homogenize(self: Self, divFac: T) Vec(N + 1, T) {
            var result = Vec(N + 1, T){ .a = undefined };
            for (0..N) |i| {
                result.a[i] = self.a[i];
            }
            result.a[N] = divFac;
            return result;
        }

        pub fn cross(self: Self, other: Self) Self {
            switch (comptime N) {
                3 => {
                    return Self{ .a = .{
                        (self.a[1] * other.a[2]) - (self.a[2] * other.a[1]),
                        (self.a[2] * other.a[0]) - (self.a[0] * other.a[2]),
                        (self.a[0] * other.a[1]) - (self.a[1] * other.a[0]),
                    } };
                },

                // Yes, there is a 7-dimensional cross product. It may be needed for 4D? --GM

                else => {
                    @compileError("cross product not supported for vector length");
                },
            }
        }
    };
}

fn Mat(comptime N: usize, comptime T: type) type {
    return struct {
        const Self = @This();
        pub const SCHEMA = .{"a"};
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
    pub const SCHEMA = .{"a"};
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

    fn _matmultype(comptime OT: type) type {
        return switch (OT) {
            Self => Self,
            f32, f64, comptime_float => Self,
            Vec4f => Vec4f,
            else => @compileError("unhandled type for mat mul"),
        };
    }
    pub fn mul(self: Self, other: anytype) _matmultype(@TypeOf(other)) {
        switch (@TypeOf(other)) {
            Self => {
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
            },

            Vec4f => {
                var result = Vec4f{ .a = undefined };
                for (0..N) |i| {
                    var total: T = 0.0;
                    for (0..N) |k| {
                        total += self.a[(k * N) + i] * other.a[k];
                    }
                    result.a[i] = total;
                }
                return result;
            },

            f32, f64, comptime_float => {
                var result = Self{ .a = undefined };
                for (0..N * N) |i| {
                    result.a[i] = self.a[i] * other;
                }
                return result;
            },

            else => @compileError("unhandled type for mat mul"),
        }
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
        const mc = (Self.I.sub(mw).sub(mb)).mul(rc);

        // sin term
        const ms = (Self{
            .a = [N * N]T{
                0.0, zn,  -yn, 0.0,
                -zn, 0.0, xn,  0.0,
                yn,  -xn, 0.0, 0.0,
                0.0, 0.0, 0.0, 0.0,
            },
        }).mul(rs);

        return mb.add(mc).add(ms).add(mw);
    }
    pub fn rotate(self: Self, ang: T, x: T, y: T, z: T) Self {
        return self.mul(genRotate(ang, x, y, z));
    }

    pub fn perspective(width: T, height: T, znear: T, zfar: T) Self {
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
