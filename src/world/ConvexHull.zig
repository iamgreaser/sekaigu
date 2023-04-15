const std = @import("std");
const log = std.log.scoped(.world_convexhull);
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const linalg = @import("../linalg.zig");
const Vec2f = linalg.Vec2f;
const Vec3f = linalg.Vec3f;
const Vec4f = linalg.Vec4f;
const Mat2f = linalg.Mat2f;
const Mat3f = linalg.Mat3f;
const Mat4f = linalg.Mat4f;
const va_types = @import("va_types.zig");
const IdxType = @import("IdxType.zig").IdxType;
const VA_P4HF_T2F_C3F_N3F = va_types.VA_P4HF_T2F_C3F_N3F;

pub const Point = @import("Point.zig").Point(ConvexHull, "points");
pub const Face = @import("Face.zig").Face(ConvexHull, "faces");
pub const Edge = @import("Edge.zig").Edge(ConvexHull, "edges", Face, Point);

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

                // NOTE: We are making a fan from the first point, and 4 infinite points in a row.
                // So the first point MUST be finite.
                // Otherwise we can get a 3-infinite point and that's... bad.

                // Refpoint
                {
                    const posw1 = f0.norm.mul(-f0.offs).homogenize(1.0);
                    const tex0w1 = Vec2f.new(.{ posw1.a[0], posw1.a[2] });
                    (try self.meshpoints.addOne()).* = VA_P4HF_T2F_C3F_N3F{
                        .pos = posw1.a,
                        .color = colorw1.a,
                        .normal = normalw1.a,
                        .tex0 = tex0w1.a,
                    };
                }

                // Now we need to make some cross product based on which edge is most major.
                const xlen = @fabs(f0.norm.a[0]);
                const ylen = @fabs(f0.norm.a[1]);
                const zlen = @fabs(f0.norm.a[2]);
                const xsign = if (f0.norm.a[0] >= 0.0) @as(f32, 1.0) else @as(f32, -1.0);
                const ysign = if (f0.norm.a[1] >= 0.0) @as(f32, 1.0) else @as(f32, -1.0);
                const zsign = if (f0.norm.a[2] >= 0.0) @as(f32, 1.0) else @as(f32, -1.0);

                var sidedir0: Vec3f = undefined;
                var sidedir1: Vec3f = undefined;
                // TODO: Extract this out for texcoord generation --GM
                // TODO: Confirm the directions are accurate for texmapping a cube --GM
                if (xlen >= ylen and xlen >= zlen) {
                    // X
                    sidedir0 = f0.norm.cross(Vec3f.new(.{ 0.0, 0.0, -1.0 }).mul(xsign));
                    sidedir1 = f0.norm.cross(Vec3f.new(.{ 0.0, 1.0, 0.0 }));
                } else if (ylen <= zlen) {
                    // Y
                    sidedir0 = f0.norm.cross(Vec3f.new(.{ 1.0, 0.0, 0.0 }));
                    sidedir1 = f0.norm.cross(Vec3f.new(.{ 0.0, 0.0, -1.0 }).mul(ysign));
                } else {
                    // Z
                    sidedir0 = f0.norm.cross(Vec3f.new(.{ 1.0, 0.0, 0.0 }).mul(zsign));
                    sidedir1 = f0.norm.cross(Vec3f.new(.{ 0.0, 1.0, 0.0 }));
                }

                // -S0
                {
                    const posw0 = sidedir0.mul(-1.0).homogenize(0.0);
                    const tex0w0 = Vec2f.new(.{ posw0.a[0], posw0.a[2] });
                    (try self.meshpoints.addOne()).* = VA_P4HF_T2F_C3F_N3F{
                        .pos = posw0.a,
                        .color = colorw0.a,
                        .normal = normalw0.a,
                        .tex0 = tex0w0.a,
                    };
                }

                // -S1
                {
                    const posw0 = sidedir1.mul(-1.0).homogenize(0.0);
                    const tex0w0 = Vec2f.new(.{ posw0.a[0], posw0.a[2] });
                    (try self.meshpoints.addOne()).* = VA_P4HF_T2F_C3F_N3F{
                        .pos = posw0.a,
                        .color = colorw0.a,
                        .normal = normalw0.a,
                        .tex0 = tex0w0.a,
                    };
                }

                // +S0
                {
                    const posw0 = sidedir0.homogenize(0.0);
                    const tex0w0 = Vec2f.new(.{ posw0.a[0], posw0.a[2] });
                    (try self.meshpoints.addOne()).* = VA_P4HF_T2F_C3F_N3F{
                        .pos = posw0.a,
                        .color = colorw0.a,
                        .normal = normalw0.a,
                        .tex0 = tex0w0.a,
                    };
                }

                // +S1
                {
                    const posw0 = sidedir1.homogenize(0.0);
                    const tex0w0 = Vec2f.new(.{ posw0.a[0], posw0.a[2] });
                    (try self.meshpoints.addOne()).* = VA_P4HF_T2F_C3F_N3F{
                        .pos = posw0.a,
                        .color = colorw0.a,
                        .normal = normalw0.a,
                        .tex0 = tex0w0.a,
                    };
                }
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

            // EDGE CASE: Add one more face for the 0-edge case
            if (edgecount == 0) {
                (try self.meshindices.addOne()).* = @intCast(u16, firstmp);
                (try self.meshindices.addOne()).* = @intCast(u16, endmp - 1);
                (try self.meshindices.addOne()).* = @intCast(u16, firstmp + 1);
            }
        }
    }
};
