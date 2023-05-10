// SPDX-License-Identifier: AGPL-3.0-or-later
//! A static pool of objects with a fixed length.

pub fn StaticPoolChainedItem(comptime Item: type) type {
    return struct {
        const Self = @This();
        prev_next_pptr: *?*Self = undefined,
        next: ?*Self = null,
        child: Item = undefined,

        pub const Iter = struct {
            current: ?*Self,

            pub fn next(iter: *Iter) ?*Self {
                if (iter.current) |result| {
                    iter.current = result.next;
                    return result;
                } else {
                    return null;
                }
            }
        };

        pub fn init(self: *Self, options: Item.InitOptions) !void {
            try self.child.init(options);
        }

        pub fn deinit(self: *Self) void {
            self.child.deinit();
        }
    };
}

pub fn StaticPool(comptime Item: type) type {
    return struct {
        const Self = @This();
        pub const ChainedItem = StaticPoolChainedItem(Item);

        // FIXME ZIGCRASH: This crashes the compiler. Using an optional type instead for now. TODO FILE BUG REPORT --GM
        //const Empty = &[0]ChainedItem{};
        //items: []ChainedItem = Empty,

        items: ?[]ChainedItem = null,
        first_free: ?*ChainedItem = null,
        first_used: ?*ChainedItem = null,

        pub fn init(self: *Self, items: []ChainedItem) void {
            self.items = items;
            var prev_next_pptr = &self.first_free;
            for (items) |*ci| {
                prev_next_pptr.* = ci;
                ci.prev_next_pptr = prev_next_pptr;
                ci.next = null;
                prev_next_pptr = &ci.next;
            }
        }

        pub fn deinit(self: *Self) void {
            while (self.first_used) |ci| {
                self.release(ci);
            }
            self.first_free = null;
            self.first_used = null;
            self.items = null;
        }

        pub fn tryAcquire(self: *Self, options: Item.InitOptions) !?*ChainedItem {
            if (self.first_free) |ci| {
                try ci.init(options);
                self.moveItemToChain(ci, &self.first_used);
                return ci;
            } else {
                return null;
            }
        }

        pub fn release(self: *Self, ci: *ChainedItem) void {
            self.moveItemToChain(ci, &self.first_free);
            if (self.first_used == ci) {
                // Just in case we introduce a bug and hit an infinite loop.
                @panic("First used chained item not released!");
            }
            ci.deinit();
        }

        pub fn iterUsed(self: *Self) ChainedItem.Iter {
            return ChainedItem.Iter{ .current = self.first_used };
        }

        fn moveItemToChain(self: *Self, ci: *ChainedItem, new_root: *?*ChainedItem) void {
            _ = self;

            // Detach
            if (ci.next) |next| {
                next.prev_next_pptr = ci.prev_next_pptr;
            }
            ci.prev_next_pptr.* = ci.next;

            // Reattach
            ci.next = new_root.*;
            ci.prev_next_pptr = new_root;
            new_root.* = ci;
            if (ci.next) |next| {
                next.prev_next_pptr = &ci.next;
            }
        }
    };
}
