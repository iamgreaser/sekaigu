//
// BASIC TERMINOLOGY:
// - Face: A potentially infinite plane, consisting of a surface normal direction and an offset from the origin (position 0,0,0).
// - Edge: A potentially infinite line, consisting of a reference point and a direction.
// - Point: A single point in 3D space.
// - Dir: A direction along 3D space.
// These terms were picked because:
// - The first letter is unambiguous.
// - The plural forms merely involve appending an "s" to the end (c.f. Vertex/Vertices).
//

const std = @import("std");
const log = std.log.scoped(.world);
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const linalg = @import("linalg.zig");
const Vec2f = linalg.Vec2f;
const Vec3f = linalg.Vec3f;
const Vec4f = linalg.Vec4f;
const Mat2f = linalg.Mat2f;
const Mat3f = linalg.Mat3f;
const Mat4f = linalg.Mat4f;

pub fn IdxType(comptime Parent: type, comptime alfield: []const u8, comptime T: type) type {
    return struct {
        const Self = @This();
        parent: *Parent,
        v: usize,
        pub fn ptr(self: *const Self) T {
            return @field(self.parent, alfield).items[self.v];
        }
    };
}

pub const Face = struct {
    const Self = @This();
    pub const Idx = IdxType(ConvexHull, "faces", Self);
    norm: Vec3f,
    offs: f32,

    pub fn calcSignedDist(self: *const Self, point: Vec3f) f32 {
        return self.norm.dot(point) + self.offs;
    }

    pub fn project(self: *const Self, point: Vec3f) Vec3f {
        return point.sub(self.norm.mul(self.calcSignedDist(point)));
    }

    pub fn projectDir(self: *const Self, point: Vec3f) Vec3f {
        return point.sub(self.norm.mul(self.norm.dot(point)));
    }
};

pub const Edge = struct {
    const Self = @This();
    pub const Idx = IdxType(ConvexHull, "edges", Self);
    refpoint: Vec3f,
    dir: Vec3f,
    face0: Face.Idx,
    face1: Face.Idx,
    point0: ?Point.Idx = null,
    point1: ?Point.Idx = null,
    degenerate: bool = false, // "true" if this edge cannot be contained within the convex hull.
};

pub const Point = struct {
    const Self = @This();
    pub const Idx = IdxType(ConvexHull, "points", Self);
    pos: Vec3f,
};

pub const ConvexHull = struct {
    // TODO! --GM
    const Self = @This();

    allocator: Allocator,
    faces: ArrayList(Face),
    edges: ArrayList(Edge),
    points: ArrayList(Point),

    pub fn init(allocator: Allocator) anyerror!Self {
        var faces = ArrayList(Face).init(allocator);
        errdefer faces.deinit();
        var edges = ArrayList(Edge).init(allocator);
        errdefer edges.deinit();
        var points = ArrayList(Point).init(allocator);
        errdefer points.deinit();

        return Self{
            .allocator = allocator,
            .faces = faces,
            .edges = edges,
            .points = points,
        };
    }

    pub fn deinit(self: *Self) void {
        self.faces.deinit();
        self.edges.deinit();
        self.points.deinit();
    }

    pub fn addFace(self: *Self, norm: Vec3f, offs: f32) !Face.Idx {
        const idx = self.faces.items.len;
        try self.faces.append(Face{
            .norm = norm,
            .offs = offs,
        });
        return Face.Idx{ .parent = self, .v = idx };
    }

    fn allocEdge(self: *Self, refpoint: Vec3f, dir: Vec3f, face0: Face.Idx, face1: Face.Idx) !Edge.Idx {
        const idx = self.edges.items.len;
        try self.edges.append(Edge{
            .refpoint = refpoint,
            .dir = dir,
            .face0 = face0,
            .face1 = face1,
        });
        return Edge.Idx{ .parent = self, .v = idx };
    }

    pub fn makeEdgeFromFaces(self: *Self, face0: Face.Idx, face1: Face.Idx) !Edge.Idx {
        const f0 = self.faces.items[face0.v];
        const f1 = self.faces.items[face1.v];

        // Dot-product
        const EPSILON = 0.0001;
        const dot = f0.norm.dot(f1.norm);
        if (@fabs(dot) > 1.0 - EPSILON) {
            return error.NoIntersection;
        }

        //
        // Direction:
        //
        // Compute the cross-product.
        // It will be perpendicular to both normals.
        //
        const dir = f0.norm.cross(f1.norm).normalize();

        //
        // Reference point:
        //
        // A: Start with the origin.
        // B: Project A onto face0.
        // C: Project face1 normal onto face0.
        // D: Raycast point B direction C into face1.
        //
        const f0point = f0.project(Vec3f.new(.{ 0, 0, 0 }));
        const f1dir = f0.projectDir(f1.norm).normalize();
        const f1dot = f1dir.dot(f1.norm);
        const f1delta = f1dir.mul(f1.calcSignedDist(f0point) / f1dot);
        const refpoint = f0point.sub(f1delta);

        // ALLOCATING - POINTERS INVALID AFTER THIS POINT
        return self.allocEdge(refpoint, dir, face0, face1);
    }
};

test "edge from 2 faces failed due to nonintersecting planes" {
    var chull = try ConvexHull.init(testing.allocator);
    defer chull.deinit();
    const face0 = try chull.addFace(Vec3f.new(.{ 0.0, 1.0, 0.0 }), 3.0);
    const face1 = try chull.addFace(Vec3f.new(.{ 0.0, 3.0, 0.0 }), -4.0);
    try testing.expectError(error.NoIntersection, chull.makeEdgeFromFaces(face0, face1));
}

test "edge from 2 faces" {
    var chull = try ConvexHull.init(testing.allocator);
    defer chull.deinit();
    const face0 = try chull.addFace(Vec3f.new(.{ 0.0, 1.0, 0.0 }), 3.0);
    const face1 = try chull.addFace(Vec3f.new(.{ 1.0, 0.0, 0.0 }), 4.0);
    const edge0 = try chull.makeEdgeFromFaces(face0, face1);
    const edge1 = try chull.makeEdgeFromFaces(face1, face0);

    // Resolve pointers
    var f0 = face0.ptr();
    var f1 = face1.ptr();
    var e0 = edge0.ptr();
    var e1 = edge1.ptr();

    // Check references
    try testing.expectEqual(face0.v, e0.face0.v);
    try testing.expectEqual(face1.v, e0.face1.v);
    try testing.expectEqual(face1.v, e1.face0.v);
    try testing.expectEqual(face0.v, e1.face1.v);
    try testing.expect(null == e0.point0);
    try testing.expect(null == e0.point1);
    try testing.expect(null == e1.point0);
    try testing.expect(null == e1.point1);

    // Check directions
    try testing.expectApproxEqAbs(@as(f32, 1.0), @fabs(e0.dir.normalize().dot(Vec3f.new(.{ 0, 0, 1 }).normalize())), 0.001);
    try testing.expectApproxEqAbs(@as(f32, 1.0), @fabs(e1.dir.normalize().dot(Vec3f.new(.{ 0, 0, 1 }).normalize())), 0.001);
    try testing.expectApproxEqAbs(@as(f32, -1.0), e0.dir.normalize().dot(e1.dir.normalize()), 0.001);

    // Check ref point
    try testing.expectApproxEqAbs(@as(f32, 0.0), f0.calcSignedDist(e0.refpoint), 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.0), f1.calcSignedDist(e0.refpoint), 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.0), e0.refpoint.sub(e1.refpoint).length(), 0.001);
}
