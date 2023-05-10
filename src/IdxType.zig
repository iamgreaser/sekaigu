// SPDX-License-Identifier: AGPL-3.0-or-later
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
