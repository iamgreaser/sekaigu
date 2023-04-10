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

pub const VA_P4HF_T2F_C3F_N3F = struct {
    pos: [4]f32,
    tex0: [2]f32,
    color: [3]f32,
    normal: [3]f32,
};

pub fn IdxType(comptime Parent: type, comptime alfield: []const u8, comptime T: type) type {
    return struct {
        const Self = @This();
        parent: *Parent,
        v: usize,
        pub fn ptr(self: *const Self) *T {
            return &@field(self.parent, alfield).items[self.v];
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

pub const Edge = struct {
    const Self = @This();
    pub const Idx = IdxType(ConvexHull, "edges", Self);
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

pub const Point = struct {
    const Self = @This();
    pub const Idx = IdxType(ConvexHull, "points", Self);
    pos: Vec3f,
};

pub const ConvexHull = struct {
    // TODO! --GM
    const Self = @This();

    allocator: Allocator = undefined,
    faces: ArrayList(Face) = undefined,
    edges: ArrayList(Edge) = undefined,
    points: ArrayList(Point) = undefined,
    meshpoints: ArrayList(VA_P4HF_T2F_C3F_N3F) = undefined,
    meshindices: ArrayList(u16) = undefined,

    pub fn new(allocator: Allocator) anyerror!Self {
        var faces = ArrayList(Face).init(allocator);
        errdefer faces.deinit();
        var edges = ArrayList(Edge).init(allocator);
        errdefer edges.deinit();
        var points = ArrayList(Point).init(allocator);
        errdefer points.deinit();
        var meshpoints = ArrayList(VA_P4HF_T2F_C3F_N3F).init(allocator);
        errdefer meshpoints.deinit();
        var meshindices = ArrayList(u16).init(allocator);
        errdefer meshindices.deinit();

        return Self{
            .allocator = allocator,
            .faces = faces,
            .edges = edges,
            .points = points,
            .meshpoints = meshpoints,
            .meshindices = meshindices,
        };
    }

    pub fn init(self: *Self, allocator: Allocator) anyerror!void {
        var faces = ArrayList(Face).init(allocator);
        errdefer faces.deinit();
        var edges = ArrayList(Edge).init(allocator);
        errdefer edges.deinit();
        var points = ArrayList(Point).init(allocator);
        errdefer points.deinit();
        var meshpoints = ArrayList(VA_P4HF_T2F_C3F_N3F).init(allocator);
        errdefer meshpoints.deinit();
        var meshindices = ArrayList(u16).init(allocator);
        errdefer meshindices.deinit();
        self.allocator = allocator;
        self.faces = faces;
        self.edges = edges;
        self.points = points;
        self.meshpoints = meshpoints;
        self.meshindices = meshindices;
    }

    pub fn deinit(self: *Self) void {
        self.faces.deinit();
        self.edges.deinit();
        self.points.deinit();
        self.meshpoints.deinit();
        self.meshindices.deinit();
    }

    // Assumes that there is a point
    pub fn assumePoint(self: *Self, pos: Vec3f, epsilon: f32) error{NotFound}!Point.Idx {
        for (self.points.items, 0..) |p, idx| {
            if (p.pos.sub(pos).length() < epsilon) {
                return Point.Idx{ .parent = self, .v = idx };
            }
        }
        return error.NotFound;
    }

    pub fn ensurePoint(self: *Self, pos: Vec3f, epsilon: f32) !Point.Idx {
        return self.assumePoint(pos, epsilon) catch |err| switch (err) {
            error.NotFound => try self.allocPoint(pos),
        };
    }

    pub fn addFace(self: *Self, norm: Vec3f, offs: f32) !Face.Idx {
        if (!std.math.approxEqAbs(f32, 1.0, norm.length(), 0.001)) {
            log.err("normal {any} {d}", .{ norm, norm.length() });
            @panic("face normal must be normalised");
        }
        const idx = self.faces.items.len;
        try self.faces.append(Face{
            .norm = norm,
            .offs = offs,
        });
        return Face.Idx{ .parent = self, .v = idx };
    }

    fn allocPoint(self: *Self, pos: Vec3f) !Point.Idx {
        const idx = self.points.items.len;
        try self.points.append(Point{
            .pos = pos,
        });
        return Point.Idx{ .parent = self, .v = idx };
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
        // NOTE: The raycast can probably still fail here.
        // If so, it returns a NoIntersection error.
        //
        const f0point = f0.project(Vec3f.new(.{ 0, 0, 0 }));
        const f1dir = f0.projectDir(f1.norm).normalize();
        const refpoint = try f1.projectRay(f0point, f1dir);

        // ALLOCATING - POINTERS INVALID AFTER THIS POINT
        return self.allocEdge(refpoint, dir, face0, face1);
    }

    pub fn addFaceToEdge(self: *Self, edge: Edge.Idx, face: Face.Idx) void {
        _ = self;
        var e = edge.ptr();
        const f = face.ptr();

        // Determine direction
        // NOTE: We hit the BACK of a face here!
        // pos(itive) = hit with ray casting forwards
        // neg(ative) = hit with ray casting backwards
        const ispos = (f.norm.dot(e.dir) >= 0.0);

        // Raycast edge into face
        const result = f.raycast(e.refpoint, e.dir) catch |err| switch (err) {
            error.NoIntersection => return,
            else => unreachable,
        };

        if (ispos) {
            if (e.limitpos) |lim| {
                if (result < lim) {
                    e.limitpos = result;
                }
            } else {
                e.limitpos = result;
            }
        } else {
            if (e.limitneg) |lim| {
                if (result > lim) {
                    e.limitneg = result;
                }
            } else {
                e.limitneg = result;
            }
        }
    }

    pub fn edgeIsDead(self: *const Self, edge: Edge.Idx) bool {
        const e = edge.ptr();

        // Check if degenerate
        if (e.limitneg) |ln| {
            if (e.limitpos) |lp| {
                return ln >= lp;
            }
        }

        // Check if points are always behind or in line with planes
        const EPSILON_PARALLEL = 0.001;
        const EPSILON_FACESIDE = 0.001;
        for (self.faces.items) |f| {
            // Are we parallel?
            if (@fabs(f.norm.dot(e.dir)) < EPSILON_PARALLEL) {
                // Yes - are we strictly in front?
                if (f.calcSignedDist(e.refpoint) > EPSILON_FACESIDE) {
                    // Yes - this edge is dead
                    return true;
                }
            } else {
                // Cast ray against plane
                // TODO! --GM
            }
        }
        return false;
    }

    pub fn buildEdgesAndPoints(self: *Self) !void {
        // Clear most lists
        self.edges.clearAndFree();
        self.points.clearAndFree();
        self.meshpoints.clearAndFree();
        self.meshindices.clearAndFree();

        // Build faces (O(f))
        for (0..self.faces.items.len) |face0i| {
            const firstedge = self.edges.items.len;

            // Build edges (O(f^2))
            const face0 = Face.Idx{ .parent = self, .v = face0i };
            nextEdge: for (0..self.faces.items.len) |face1i| {
                if (face0i != face1i) {
                    const face1 = Face.Idx{ .parent = self, .v = face1i };
                    const edge = self.makeEdgeFromFaces(face0, face1) catch |err| switch (err) {
                        error.NoIntersection => break :nextEdge,
                        else => return err,
                    };
                    for (0..self.faces.items.len) |face2i| {
                        if (face2i != face0i and face2i != face1i) {
                            const face2 = Face.Idx{ .parent = self, .v = face2i };
                            self.addFaceToEdge(edge, face2);
                        }
                    }

                    var e = edge.ptr();

                    // If this edge is degenerate, kill it.
                    if (self.edgeIsDead(edge)) {
                        //log.warn("degenerate edge {any} {any} {any} {any} {any} {any}", .{ e.face0.ptr(), e.face1.ptr(), e.limitneg, e.limitpos, e.refpoint.a, e.dir.a });
                        //log.warn("degenerate edge", .{});
                        if (edge.v != self.edges.items.len - 1) @panic("attempted to remove nonfinal edge in bake!");
                        _ = self.edges.swapRemove(edge.v);
                        if (edge.v != self.edges.items.len) @panic("attempted to remove more than one edge in bake!");
                    } else {
                        // Otherwise, build the endpoints.
                        const EPSILON = 0.001;
                        if (e.getNegPoint()) |pn|
                            e.limitnegpoint = try self.ensurePoint(pn, EPSILON);
                        if (e.getPosPoint()) |pp|
                            e.limitpospoint = try self.ensurePoint(pp, EPSILON);
                    }
                }
            }

            // Build our edge list
            const endedge = self.edges.items.len;
            const edgecount = endedge - firstedge;
            //log.warn("face edges {}..{} {} --- {any}", .{ firstedge, endedge, edgecount, face0.ptr() });

            //
            // Look for edge cases (har har)
            //
            // AFAIK this is how it works:
            //
            // The cases are:
            // - 0 edges (project the origin, add 3 or 4 infinite points, then make triangles which all touch the origin)
            // - 1 infinite edge (use the reference point, add 2 infinite points on the line, add 1 infinite point perpendicular while inline, then make 2 triangles all touching the reference point)
            // - 2 infinite opposing edges (use 1 reference point, add 4 infinite points on both lines, then make 3 triangles all touching the reference point we used)
            // - Open strip (add 2 infinite points to represent the infinites, then build a strip from the infinite line down to the middle)
            // - Closed loop (without adding our infinite points, build a strip starting from the first point and last point down to the middle)
            // We can do both of these in the exact same way EXCEPT we need to create 2 infinite points.
            //
            // But first, special cases!
            //

            const f0 = face0.ptr();
            const firstmp = self.meshpoints.items.len;

            // w1 = finite, w0 = infinite
            const normalw1 = f0.norm;
            const normalw0 = Vec3f.new(.{ 0, 0, 0 });
            const colorw1 = Vec3f.new(.{ 1.0, 1.0, 1.0 }); // TODO! --GM
            const colorw0 = Vec3f.new(.{ 0, 0, 0 });

            if (edgecount == 0) {
                // 0 edges
                if (true) @panic("TODO: 0-edge case --GM");
            } else if (edgecount == 1 or (edgecount == 2 and self.edges.items[firstedge].limitneg == null and self.edges.items[firstedge].limitpos == null)) {
                // 1 or 2 infinite edges
                const e0 = self.edges.items[firstedge];
                if (!(e0.limitneg == null and e0.limitpos == null)) @panic("Invalid special case!");

                // NOTE: We are making a fan from the first point, and possibly 3 infinite points in a row.
                // So the first point MUST be finite.
                // Otherwise we can get a 3-infinite point and that's... bad.

                // Refpoint
                {
                    const posw1 = e0.refpoint.homogenize(1.0);
                    const tex0w1 = Vec2f.new(.{ posw1.a[0], posw1.a[2] });
                    (try self.meshpoints.addOne()).* = VA_P4HF_T2F_C3F_N3F{
                        .pos = posw1.a,
                        .color = colorw1.a,
                        .normal = normalw1.a,
                        .tex0 = tex0w1.a,
                    };
                }

                // Positive
                {
                    const posw0 = e0.dir.homogenize(0.0);
                    const tex0w0 = Vec2f.new(.{ posw0.a[0], posw0.a[2] });
                    (try self.meshpoints.addOne()).* = VA_P4HF_T2F_C3F_N3F{
                        .pos = posw0.a,
                        .color = colorw0.a,
                        .normal = normalw0.a,
                        .tex0 = tex0w0.a,
                    };
                }

                // Side
                if (edgecount == 2) {
                    const e1 = self.edges.items[firstedge + 1];
                    if (!(e1.limitneg == null and e1.limitpos == null)) @panic("Invalid special case!");

                    // Side Negative
                    {
                        const posw0 = e1.dir.mul(-1.0).homogenize(0.0);
                        const tex0w0 = Vec2f.new(.{ posw0.a[0], posw0.a[2] });
                        (try self.meshpoints.addOne()).* = VA_P4HF_T2F_C3F_N3F{
                            .pos = posw0.a,
                            .color = colorw0.a,
                            .normal = normalw0.a,
                            .tex0 = tex0w0.a,
                        };
                    }

                    // Side Refpoint
                    // NOTE: This is actually required!
                    {
                        const posw1 = e1.refpoint.homogenize(1.0);
                        const tex0w1 = Vec2f.new(.{ posw1.a[0], posw1.a[2] });
                        (try self.meshpoints.addOne()).* = VA_P4HF_T2F_C3F_N3F{
                            .pos = posw1.a,
                            .color = colorw1.a,
                            .normal = normalw1.a,
                            .tex0 = tex0w1.a,
                        };
                    }

                    // Side Positive
                    {
                        const posw0 = e1.dir.homogenize(0.0);
                        const tex0w0 = Vec2f.new(.{ posw0.a[0], posw0.a[2] });
                        (try self.meshpoints.addOne()).* = VA_P4HF_T2F_C3F_N3F{
                            .pos = posw0.a,
                            .color = colorw0.a,
                            .normal = normalw0.a,
                            .tex0 = tex0w0.a,
                        };
                    }
                } else {
                    // Find other face
                    const f1 = if (face0.v == e0.face0.v)
                        e0.face1.ptr()
                    else if (face0.v == e0.face1.v)
                        e0.face0.ptr()
                    else
                        unreachable;

                    // Project negative of f1 normal direction onto f0
                    const sidedir = f0.projectDir(f1.norm.mul(-1.0)).normalize();

                    // Side
                    {
                        const posw0 = sidedir.homogenize(0.0);
                        const tex0w0 = Vec2f.new(.{ posw0.a[0], posw0.a[2] });
                        (try self.meshpoints.addOne()).* = VA_P4HF_T2F_C3F_N3F{
                            .pos = posw0.a,
                            .color = colorw0.a,
                            .normal = normalw0.a,
                            .tex0 = tex0w0.a,
                        };
                    }
                }

                // Negative
                {
                    const posw0 = e0.dir.mul(-1.0).homogenize(0.0);
                    const tex0w0 = Vec2f.new(.{ posw0.a[0], posw0.a[2] });
                    (try self.meshpoints.addOne()).* = VA_P4HF_T2F_C3F_N3F{
                        .pos = posw0.a,
                        .color = colorw0.a,
                        .normal = normalw0.a,
                        .tex0 = tex0w0.a,
                    };
                }
            } else {
                // Open strip or closed loop
                // Add all points
                {
                    var curedge = self.edges.items[firstedge];

                    for (0..edgecount) |_| {
                        // Add the negative point to the edge list
                        // TEST: Use x,z directly --GM
                        if (curedge.limitnegpoint) |lnpoint| {
                            const posw1 = lnpoint.ptr().pos.homogenize(1.0);
                            const tex0w1 = Vec2f.new(.{ posw1.a[0], posw1.a[2] });
                            (try self.meshpoints.addOne()).* = VA_P4HF_T2F_C3F_N3F{
                                .pos = posw1.a,
                                .color = colorw1.a,
                                .normal = normalw1.a,
                                .tex0 = tex0w1.a,
                            };
                        } else {
                            const posw0 = curedge.dir.mul(-1.0).homogenize(0.0);
                            const tex0w0 = Vec2f.new(.{ -curedge.dir.a[0], -curedge.dir.a[2] });
                            (try self.meshpoints.addOne()).* = VA_P4HF_T2F_C3F_N3F{
                                .pos = posw0.a,
                                .color = colorw0.a,
                                .normal = normalw0.a,
                                .tex0 = tex0w0.a,
                            };
                        }

                        // If we have a positive point, we add another point
                        if (curedge.limitpospoint == null) {
                            //
                            //const lnpoint = curedge.limitnegpoint orelse unreachable;
                            const posw0 = curedge.dir.homogenize(0.0);
                            const tex0w0 = Vec2f.new(.{ curedge.dir.a[0], curedge.dir.a[2] });
                            (try self.meshpoints.addOne()).* = VA_P4HF_T2F_C3F_N3F{
                                .pos = posw0.a,
                                .color = colorw0.a,
                                .normal = normalw0.a,
                                .tex0 = tex0w0.a,
                            };
                        }

                        // Find the next edge
                        if (curedge.limitpospoint) |lppoint| {
                            const nextpti = lppoint.v;
                            curedge = gotEdge: {
                                for (firstedge..endedge) |nexti| {
                                    const nextedge = self.edges.items[nexti];
                                    if (nextedge.limitnegpoint) |lnpoint| {
                                        if (lnpoint.v == nextpti) {
                                            break :gotEdge nextedge;
                                        }
                                    }
                                }
                                @panic("edge loop not found");
                            };
                        } else {
                            curedge = gotEdge: {
                                for (firstedge..endedge) |nexti| {
                                    const nextedge = self.edges.items[nexti];
                                    if (nextedge.limitnegpoint == null) {
                                        break :gotEdge nextedge;
                                    }
                                }
                                @panic("edge loop not found");
                            };
                        }
                    }
                }
            }

            // Form a fan
            const endmp = self.meshpoints.items.len;
            //const mpcount = endmp - firstmp;
            for (firstmp + 1..endmp - 1) |fanidx| {
                (try self.meshindices.addOne()).* = @intCast(u16, firstmp);
                (try self.meshindices.addOne()).* = @intCast(u16, fanidx + 0);
                (try self.meshindices.addOne()).* = @intCast(u16, fanidx + 1);
            }
        }
    }
};

test "edge from 2 faces failed due to nonintersecting planes" {
    var chull = try ConvexHull.new(testing.allocator);
    defer chull.deinit();
    const face0 = try chull.addFace(Vec3f.new(.{ 0.0, 1.0, 0.0 }).normalize(), 3.0);
    const face1 = try chull.addFace(Vec3f.new(.{ 0.0, 3.0, 0.0 }).normalize(), -4.0);
    try testing.expectError(error.NoIntersection, chull.makeEdgeFromFaces(face0, face1));
}

test "edge from 2 faces" {
    var chull = try ConvexHull.new(testing.allocator);
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
    try testing.expect(e0.limitpos == null);
    try testing.expect(e0.limitneg == null);
    try testing.expect(e1.limitpos == null);
    try testing.expect(e1.limitneg == null);

    // Check directions
    try testing.expectApproxEqAbs(@as(f32, 1.0), @fabs(e0.dir.normalize().dot(Vec3f.new(.{ 0, 0, 1 }).normalize())), 0.001);
    try testing.expectApproxEqAbs(@as(f32, 1.0), @fabs(e1.dir.normalize().dot(Vec3f.new(.{ 0, 0, 1 }).normalize())), 0.001);
    try testing.expectApproxEqAbs(@as(f32, -1.0), e0.dir.normalize().dot(e1.dir.normalize()), 0.001);

    // Check ref point
    try testing.expectApproxEqAbs(@as(f32, 0.0), f0.calcSignedDist(e0.refpoint), 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.0), f1.calcSignedDist(e0.refpoint), 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.0), e0.refpoint.sub(e1.refpoint).length(), 0.001);
}

test "edge from 3 faces forming 1 point" {
    var chull = try ConvexHull.new(testing.allocator);
    defer chull.deinit();
    const face0 = try chull.addFace(Vec3f.new(.{ 0.0, 1.0, 0.0 }), 3.0);
    const face1 = try chull.addFace(Vec3f.new(.{ 1.0, 0.0, 0.0 }), 4.0);
    const face2 = try chull.addFace(Vec3f.new(.{ 0.0, 0.0, 1.0 }), 5.0);
    const edge0 = try chull.makeEdgeFromFaces(face0, face1);
    const edge1 = try chull.makeEdgeFromFaces(face1, face0);
    chull.addFaceToEdge(edge0, face2);
    chull.addFaceToEdge(edge1, face2);

    // Resolve pointers
    var e0 = edge0.ptr();
    var e1 = edge1.ptr();

    // Check references
    try testing.expect((e0.limitpos == null) != (e0.limitneg == null));
    try testing.expect((e0.limitpos != null) == (e1.limitneg != null));
    try testing.expect((e0.limitneg == null) == (e1.limitpos == null));
    try testing.expect(e0.limitpos == null);
    try testing.expect(e0.limitneg != null);
    try testing.expect(e1.limitpos != null);
    try testing.expect(e1.limitneg == null);
    try testing.expectApproxEqAbs(@as(f32, 5.0), e0.limitneg orelse unreachable, 0.001);
    try testing.expectApproxEqAbs(@as(f32, -5.0), e1.limitpos orelse unreachable, 0.001);
}

test "edge from 4 faces forming 2 points" {
    var chull = try ConvexHull.new(testing.allocator);
    defer chull.deinit();
    const face0 = try chull.addFace(Vec3f.new(.{ 0.0, 1.0, 0.0 }), 3.0);
    const face1 = try chull.addFace(Vec3f.new(.{ 1.0, 0.0, 0.0 }), 4.0);
    const face2 = try chull.addFace(Vec3f.new(.{ 0.0, 0.0, 1.0 }), -5.0);
    const face3 = try chull.addFace(Vec3f.new(.{ 0.0, 0.0, -1.0 }), -7.0);
    const edge0 = try chull.makeEdgeFromFaces(face0, face1);
    const edge1 = try chull.makeEdgeFromFaces(face1, face0);
    chull.addFaceToEdge(edge0, face2);
    chull.addFaceToEdge(edge0, face3);
    chull.addFaceToEdge(edge1, face2);
    chull.addFaceToEdge(edge1, face3);

    // Resolve pointers
    var e0 = edge0.ptr();
    var e1 = edge1.ptr();

    // Check references
    try testing.expect(e0.limitpos != null);
    try testing.expect(e0.limitneg != null);
    try testing.expect(e1.limitpos != null);
    try testing.expect(e1.limitneg != null);
    try testing.expect(e0.limitneg orelse unreachable < e0.limitpos orelse unreachable);
    try testing.expect(e1.limitneg orelse unreachable < e1.limitpos orelse unreachable);
    try testing.expectApproxEqAbs(@as(f32, 7.0), e0.limitpos orelse unreachable, 0.001);
    try testing.expectApproxEqAbs(@as(f32, -5.0), e0.limitneg orelse unreachable, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 5.0), e1.limitpos orelse unreachable, 0.001);
    try testing.expectApproxEqAbs(@as(f32, -7.0), e1.limitneg orelse unreachable, 0.001);
}

test "edge from 4 faces forming degenerate" {
    var chull = try ConvexHull.new(testing.allocator);
    defer chull.deinit();
    const face0 = try chull.addFace(Vec3f.new(.{ 0.0, 1.0, 0.0 }), 3.0);
    const face1 = try chull.addFace(Vec3f.new(.{ 1.0, 0.0, 0.0 }), 4.0);
    const face2 = try chull.addFace(Vec3f.new(.{ 0.0, 0.0, 1.0 }), 5.0);
    const face3 = try chull.addFace(Vec3f.new(.{ 0.0, 0.0, -1.0 }), 5.0);
    const edge0 = try chull.makeEdgeFromFaces(face0, face1);
    const edge1 = try chull.makeEdgeFromFaces(face1, face0);
    chull.addFaceToEdge(edge0, face2);
    chull.addFaceToEdge(edge0, face3);
    chull.addFaceToEdge(edge1, face2);
    chull.addFaceToEdge(edge1, face3);

    // Resolve pointers
    var e0 = edge0.ptr();
    var e1 = edge1.ptr();

    // Check references
    try testing.expect(e0.limitpos != null);
    try testing.expect(e0.limitneg != null);
    try testing.expect(e1.limitpos != null);
    try testing.expect(e1.limitneg != null);
    try testing.expect(!(e0.limitneg orelse unreachable < e0.limitpos orelse unreachable));
    try testing.expect(!(e1.limitneg orelse unreachable < e1.limitpos orelse unreachable));
}

test "edge from 4 faces forming 1 point, far then near" {
    var chull = try ConvexHull.new(testing.allocator);
    defer chull.deinit();
    const face0 = try chull.addFace(Vec3f.new(.{ 0.0, 1.0, 0.0 }), 3.0);
    const face1 = try chull.addFace(Vec3f.new(.{ 1.0, 0.0, 0.0 }), 4.0);
    const face2 = try chull.addFace(Vec3f.new(.{ 0.0, 1.0, 1.0 }).normalize(), -10.0);
    const face3 = try chull.addFace(Vec3f.new(.{ 0.0, 0.0, 1.0 }), -2.0);
    const edge0 = try chull.makeEdgeFromFaces(face0, face1);
    const edge1 = try chull.makeEdgeFromFaces(face1, face0);
    chull.addFaceToEdge(edge0, face2);
    chull.addFaceToEdge(edge0, face3);
    chull.addFaceToEdge(edge1, face2);
    chull.addFaceToEdge(edge1, face3);

    // Resolve pointers
    var e0 = edge0.ptr();
    var e1 = edge1.ptr();

    // Check references
    try testing.expect((e0.limitpos == null) != (e0.limitneg == null));
    try testing.expect((e0.limitpos != null) == (e1.limitneg != null));
    try testing.expect((e0.limitneg == null) == (e1.limitpos == null));
    try testing.expect(e0.limitpos == null);
    try testing.expect(e0.limitneg != null);
    try testing.expect(e1.limitpos != null);
    try testing.expect(e1.limitneg == null);
    try testing.expectApproxEqAbs(@as(f32, -2.0), e0.limitneg orelse unreachable, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 2.0), e1.limitpos orelse unreachable, 0.001);
}

test "edge from 4 faces forming 1 point, near then far" {
    var chull = try ConvexHull.new(testing.allocator);
    defer chull.deinit();
    const face0 = try chull.addFace(Vec3f.new(.{ 0.0, 1.0, 0.0 }), 3.0);
    const face1 = try chull.addFace(Vec3f.new(.{ 1.0, 0.0, 0.0 }), 4.0);
    const face2 = try chull.addFace(Vec3f.new(.{ 0.0, 0.0, 1.0 }), -2.0);
    const face3 = try chull.addFace(Vec3f.new(.{ 0.0, 1.0, 1.0 }).normalize(), -10.0);
    const edge0 = try chull.makeEdgeFromFaces(face0, face1);
    const edge1 = try chull.makeEdgeFromFaces(face1, face0);
    chull.addFaceToEdge(edge0, face2);
    chull.addFaceToEdge(edge0, face3);
    chull.addFaceToEdge(edge1, face2);
    chull.addFaceToEdge(edge1, face3);

    // Resolve pointers
    var e0 = edge0.ptr();
    var e1 = edge1.ptr();

    // Check references
    try testing.expect((e0.limitpos == null) != (e0.limitneg == null));
    try testing.expect((e0.limitpos != null) == (e1.limitneg != null));
    try testing.expect((e0.limitneg == null) == (e1.limitpos == null));
    try testing.expect(e0.limitpos == null);
    try testing.expect(e0.limitneg != null);
    try testing.expect(e1.limitpos != null);
    try testing.expect(e1.limitneg == null);
    try testing.expectApproxEqAbs(@as(f32, -2.0), e0.limitneg orelse unreachable, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 2.0), e1.limitpos orelse unreachable, 0.001);
}

test "bake a pyramid" {
    var chull = try ConvexHull.new(testing.allocator);
    defer chull.deinit();
    _ = try chull.addFace(Vec3f.new(.{ 0.0, -1.0, 0.0 }), 0.0);
    _ = try chull.addFace(Vec3f.new(.{ -1.0, 1.0, 0.0 }).normalize(), -5.0 * @sqrt(2.0) / 2.0);
    _ = try chull.addFace(Vec3f.new(.{ 1.0, 1.0, 0.0 }).normalize(), -5.0 * @sqrt(2.0) / 2.0);
    _ = try chull.addFace(Vec3f.new(.{ 0.0, 1.0, -1.0 }).normalize(), -5.0 * @sqrt(2.0) / 2.0);
    _ = try chull.addFace(Vec3f.new(.{ 0.0, 1.0, 1.0 }).normalize(), -5.0 * @sqrt(2.0) / 2.0);
    try chull.buildEdgesAndPoints();
    // Use this to check if the points are correct if they aren't --GM
    if (false) {
        log.warn("test: ", .{});
        for (chull.points.items) |p| {
            log.warn("test: {any}", .{p});
        }
    }
    try testing.expectEqual(@as(usize, 5), chull.faces.items.len);
    // Generates our 8 edges doubled... and 2 degenerate edges doubled which are based on the two pairs of opposing sloped faces.
    try testing.expectEqual(@as(usize, 8 * 2), chull.edges.items.len);
    try testing.expectEqual(@as(usize, 5), chull.points.items.len);
    const points = [_]Point.Idx{
        try chull.assumePoint(Vec3f.new(.{ 0.0, 5.0, 0.0 }), 0.001),
        try chull.assumePoint(Vec3f.new(.{ -5.0, 0.0, -5.0 }), 0.001),
        try chull.assumePoint(Vec3f.new(.{ -5.0, 0.0, 5.0 }), 0.001),
        try chull.assumePoint(Vec3f.new(.{ 5.0, 0.0, -5.0 }), 0.001),
        try chull.assumePoint(Vec3f.new(.{ 5.0, 0.0, 5.0 }), 0.001),
    };
    for (&points) |*p0| {
        for (&points) |*p1| {
            try testing.expect(p0 == p1 or p0.v != p1.v);
        }
    }

    // TODO: Look further into meshpoints and meshindices --GM
    try testing.expectEqual(@as(usize, 1 * (4 + 3 + 3 + 3 + 3)), chull.meshpoints.items.len);
    try testing.expectEqual(@as(usize, 3 * (2 + 1 + 1 + 1 + 1)), chull.meshindices.items.len);
}

test "bake an open baseless pyramid" {
    var chull = try ConvexHull.new(testing.allocator);
    defer chull.deinit();
    _ = try chull.addFace(Vec3f.new(.{ -1.0, 1.0, 0.0 }).normalize(), -5.0 * @sqrt(2.0) / 2.0);
    _ = try chull.addFace(Vec3f.new(.{ 1.0, 1.0, 0.0 }).normalize(), -5.0 * @sqrt(2.0) / 2.0);
    _ = try chull.addFace(Vec3f.new(.{ 0.0, 1.0, -1.0 }).normalize(), -5.0 * @sqrt(2.0) / 2.0);
    _ = try chull.addFace(Vec3f.new(.{ 0.0, 1.0, 1.0 }).normalize(), -5.0 * @sqrt(2.0) / 2.0);
    try chull.buildEdgesAndPoints();

    try testing.expectEqual(@as(usize, 4), chull.faces.items.len);
    // Generates our 8 edges doubled... and 2 degenerate edges doubled which are based on the two pairs of opposing sloped faces.
    try testing.expectEqual(@as(usize, 4 * 2), chull.edges.items.len);
    try testing.expectEqual(@as(usize, 1), chull.points.items.len);
    const points = [_]Point.Idx{
        try chull.assumePoint(Vec3f.new(.{ 0.0, 5.0, 0.0 }), 0.001),
    };
    for (&points) |*p0| {
        for (&points) |*p1| {
            try testing.expect(p0 == p1 or p0.v != p1.v);
        }
    }

    // TODO: Look further into meshpoints and meshindices --GM
    try testing.expectEqual(@as(usize, 1 * (3 + 3 + 3 + 3)), chull.meshpoints.items.len);
    try testing.expectEqual(@as(usize, 3 * (1 + 1 + 1 + 1)), chull.meshindices.items.len);
}

test "bake 2 planes connected by 1 parallel edge" {
    var chull = try ConvexHull.new(testing.allocator);
    defer chull.deinit();
    _ = try chull.addFace(Vec3f.new(.{ -1.0, 1.0, 0.0 }).normalize(), -5.0 * @sqrt(2.0));
    _ = try chull.addFace(Vec3f.new(.{ 1.0, 1.0, 0.0 }).normalize(), -5.0 * @sqrt(2.0));
    try chull.buildEdgesAndPoints();

    try testing.expectEqual(@as(usize, 2), chull.faces.items.len);
    try testing.expectEqual(@as(usize, 1 * 2), chull.edges.items.len);
    try testing.expectEqual(@as(usize, 0), chull.points.items.len);

    // TODO: Look further into meshpoints and meshindices --GM
    try testing.expectEqual(@as(usize, 1 * (4 + 4)), chull.meshpoints.items.len);
    try testing.expectEqual(@as(usize, 3 * (2 + 2)), chull.meshindices.items.len);
}

test "bake 3 planes connected by 2 parallel edges" {
    var chull = try ConvexHull.new(testing.allocator);
    defer chull.deinit();
    _ = try chull.addFace(Vec3f.new(.{ -1.0, 1.0, 0.0 }).normalize(), -5.0 * @sqrt(2.0));
    _ = try chull.addFace(Vec3f.new(.{ 0.0, 1.0, 0.0 }).normalize(), -2.0);
    _ = try chull.addFace(Vec3f.new(.{ 1.0, 1.0, 0.0 }).normalize(), -5.0 * @sqrt(2.0));
    try chull.buildEdgesAndPoints();

    try testing.expectEqual(@as(usize, 3), chull.faces.items.len);
    try testing.expectEqual(@as(usize, 2 * 2), chull.edges.items.len);
    try testing.expectEqual(@as(usize, 0), chull.points.items.len);

    // TODO: Look further into meshpoints and meshindices --GM
    try testing.expectEqual(@as(usize, 1 * (4 + 6 + 4)), chull.meshpoints.items.len);
    try testing.expectEqual(@as(usize, 3 * (2 + 4 + 2)), chull.meshindices.items.len);
}
