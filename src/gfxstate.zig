const std = @import("std");
const log = std.log.scoped(.gfxstate);
const Allocator = std.mem.Allocator;
const gl = @import("gl.zig");
const linalg = @import("linalg.zig");
const Vec2f = linalg.Vec2f;
const Vec3f = linalg.Vec3f;
const Vec4f = linalg.Vec4f;
const Mat2f = linalg.Mat2f;
const Mat3f = linalg.Mat3f;
const Mat4f = linalg.Mat4f;
const world = @import("world.zig");
const ConvexHull = world.ConvexHull;

pub fn Model(comptime VAType: type, comptime IndexT: type) type {
    return struct {
        pub const Self = @This();

        va: []const VAType,
        idx_list: []const IndexT,
        allocator: ?Allocator = null,
        va_owned: ?[]VAType = null,
        idx_list_owned: ?[]IndexT = null,
        va_vbo: gl.BO = gl.BO.Dummy,
        idx_vbo: gl.BO = gl.BO.Dummy,

        pub fn fromConvexHullPlanes(allocator: Allocator, normals: []const [4]f32) !Self {
            var chull: *ConvexHull = try allocator.create(ConvexHull);
            defer allocator.destroy(chull);
            try chull.init(allocator);
            defer chull.deinit();
            for (normals) |normal| {
                const x = normal[0];
                const y = normal[1];
                const z = normal[2];
                const offs = normal[3];
                const length = @sqrt(x * x + y * y + z * z);
                _ = try chull.addFace(Vec3f.new(.{ x / length, y / length, z / length }).normalize(), offs * length);
            }
            try chull.buildEdgesAndPoints();
            log.info("Baked convex hull: {} points, {} indices", .{
                chull.meshpoints.items.len,
                chull.meshindices.items.len,
            });
            return Self.fromConvexHull(allocator, chull);
        }

        pub fn fromConvexHull(allocator: Allocator, chull: *ConvexHull) !Self {
            var va = try allocator.alloc(VAType, chull.meshpoints.items.len);
            errdefer allocator.free(va);
            std.mem.copy(VAType, va, chull.meshpoints.items);
            var idx_list = try allocator.alloc(IndexT, chull.meshindices.items.len);
            errdefer allocator.free(idx_list);
            std.mem.copy(IndexT, idx_list, chull.meshindices.items);
            var result = Self{
                .allocator = allocator,
                .va = va,
                .va_owned = va,
                .idx_list = idx_list,
                .idx_list_owned = idx_list,
            };
            return result;
        }

        pub fn deinit(self: *Self) !void {
            if (self.allocator != null) |allocator| {
                if (self.va_owned != null) |p| {
                    allocator.free(p);
                    self.va_owned = null;
                }
                if (self.idx_list_owned != null) |p| {
                    allocator.free(p);
                    self.idx_list_owned = null;
                }
            }
        }

        pub fn load(self: *Self) !void {
            {
                self.va_vbo = try gl.BO.genBuffer();
                try gl.bindBuffer(.ArrayBuffer, self.va_vbo);
                defer gl.unbindBuffer(.ArrayBuffer) catch {};
                try gl.bufferData(.ArrayBuffer, VAType, self.va, .StaticDraw);
            }
            {
                self.idx_vbo = try gl.BO.genBuffer();
                try gl.bindBuffer(.ElementArrayBuffer, self.idx_vbo);
                defer gl.unbindBuffer(.ElementArrayBuffer) catch {};
                try gl.bufferData(.ElementArrayBuffer, IndexT, self.idx_list, .StaticDraw);
            }
        }

        pub fn draw(
            self: Self,
            mode: gl.DrawMode,
        ) !void {
            try gl.bindBuffer(.ArrayBuffer, self.va_vbo);
            defer gl.unbindBuffer(.ArrayBuffer) catch {};
            try gl.bindBuffer(.ElementArrayBuffer, self.idx_vbo);
            defer gl.unbindBuffer(.ElementArrayBuffer) catch {};

            defer {
                inline for (@typeInfo(VAType).Struct.fields, 0..) |_, i| {
                    gl.disableVertexAttribArray(i) catch {};
                }
            }
            inline for (@typeInfo(VAType).Struct.fields, 0..) |field, i| {
                try gl.vertexAttribPointer(i, VAType, field.name);
                try gl.enableVertexAttribArray(i);
            }
            try gl.drawElements(mode, 0, self.idx_list.len, IndexT);
            //try gl.drawArrays(mode, 0, self.va.len);
        }
    };
}

pub var shader_uniforms: struct {
    mproj: Mat4f = Mat4f.perspective(800.0, 600.0, 0.01, 1000.0),
    mcam: Mat4f = Mat4f.I,
    mmodel: Mat4f = Mat4f.I,
    light: Vec4f = Vec4f.new(.{ 0.0, 0.0, 0.0, 1.0 }),
    cam_pos: Vec4f = Vec4f.new(.{ 0.0, 0.0, 0.0, 1.0 }),
    smp0: gl.Sampler2D = gl.Sampler2D.makeSampler(0),
    font_color: Vec4f = Vec4f.new(.{ 1.0, 1.0, 1.0, 1.0 }),
} = .{};
