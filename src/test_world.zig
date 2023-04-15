const std = @import("std");
const log = std.log.scoped(.test_world_convexhull);
const testing = std.testing;
const linalg = @import("linalg.zig");
const Vec2f = linalg.Vec2f;
const Vec3f = linalg.Vec3f;
const Vec4f = linalg.Vec4f;
const Mat2f = linalg.Mat2f;
const Mat3f = linalg.Mat3f;
const Mat4f = linalg.Mat4f;

const world = @import("world.zig");
const ConvexHull = world.ConvexHull;
const Point = world.convex_hull.Point;

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

test "bake 1 plane, -Z" {
    var chull = try ConvexHull.new(testing.allocator);
    defer chull.deinit();
    _ = try chull.addFace(Vec3f.new(.{ 0.0, 0.0, -1.0 }).normalize(), -5.0);
    try chull.buildEdgesAndPoints();

    try testing.expectEqual(@as(usize, 1), chull.faces.items.len);
    try testing.expectEqual(@as(usize, 0 * 2), chull.edges.items.len);
    try testing.expectEqual(@as(usize, 0), chull.points.items.len);

    // TODO: Look further into meshpoints and meshindices --GM
    try testing.expectEqual(@as(usize, 1 * (5)), chull.meshpoints.items.len);
    try testing.expectEqual(@as(usize, 3 * (4)), chull.meshindices.items.len);
}

test "bake 1 plane, +Y" {
    var chull = try ConvexHull.new(testing.allocator);
    defer chull.deinit();
    _ = try chull.addFace(Vec3f.new(.{ 0.0, 1.0, 0.0 }).normalize(), -5.0);
    try chull.buildEdgesAndPoints();

    try testing.expectEqual(@as(usize, 1), chull.faces.items.len);
    try testing.expectEqual(@as(usize, 0 * 2), chull.edges.items.len);
    try testing.expectEqual(@as(usize, 0), chull.points.items.len);

    // TODO: Look further into meshpoints and meshindices --GM
    try testing.expectEqual(@as(usize, 1 * (5)), chull.meshpoints.items.len);
    try testing.expectEqual(@as(usize, 3 * (4)), chull.meshindices.items.len);
}

test "bake 1 plane, +X" {
    var chull = try ConvexHull.new(testing.allocator);
    defer chull.deinit();
    _ = try chull.addFace(Vec3f.new(.{ 1.0, 0.0, 0.0 }).normalize(), -5.0);
    try chull.buildEdgesAndPoints();

    try testing.expectEqual(@as(usize, 1), chull.faces.items.len);
    try testing.expectEqual(@as(usize, 0 * 2), chull.edges.items.len);
    try testing.expectEqual(@as(usize, 0), chull.points.items.len);

    // TODO: Look further into meshpoints and meshindices --GM
    try testing.expectEqual(@as(usize, 1 * (5)), chull.meshpoints.items.len);
    try testing.expectEqual(@as(usize, 3 * (4)), chull.meshindices.items.len);
}
