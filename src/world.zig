// SPDX-License-Identifier: AGPL-3.0-or-later
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

pub const va_types = @import("world/va_types.zig");
pub const VA_P4HF_T2F_C3F_N3F = va_types.VA_P4HF_T2F_C3F_N3F;
pub const convex_hull = @import("world/ConvexHull.zig");
pub const ConvexHull = convex_hull.ConvexHull;
