// SPDX-License-Identifier: AGPL-3.0-or-later
const std = @import("std");
const log = std.log.scoped(.schema);
const AutoHashMap = std.AutoHashMap;

pub fn save(comptime TWriter: type, writer: *TWriter, comptime T: type, value: *T) !void {
    switch (@typeInfo(T)) {
        .Pointer => |ti| {
            try save(TWriter, writer, ti.child, value.*);
        },

        .Array => |ti| {
            const count: usize = ti.len;
            const V = ti.child;
            try saveTag(TWriter, writer, .List, count);
            for (value) |*subv| {
                try save(TWriter, writer, V, subv);
            }
        },

        .Int => |ti| {
            if (ti.signedness == .signed) {
                const Unsigned = @Type(.{ .Int = .{ .signedness = .unsigned, .bits = ti.bits } });
                if (value < 0) {
                    try saveIntPart(TWriter, writer, Unsigned, @intCast(Unsigned, -1 - value.*), true);
                } else {
                    try saveIntPart(TWriter, writer, Unsigned, @intCast(Unsigned, value.*), false);
                }
            } else {
                try saveIntPart(TWriter, writer, T, @intCast(T, value.*), false);
            }
        },

        .Float => switch (T) {
            f32 => try writer.writeIntLittle(u32, @bitCast(u32, value.*)),
            f64 => try writer.writeIntLittle(u32, @bitCast(u32, value.*)),
            else => {
                log.err("save: Unhandled float type {any}", .{T});
                return error.UnhandledType;
            },
        },

        .Struct => {
            if (@hasDecl(T, "SCHEMA")) {
                // Something we handle directly.
                inline for (T.SCHEMA) |name| {
                    const fv = &@field(value, name);
                    try save(TWriter, writer, @TypeOf(fv.*), fv);
                }
            } else if (@hasDecl(T, "getKey") and @hasDecl(T, "get")) {
                // Probably a map.
                const KOpt = @typeInfo(@TypeOf(T.getKey)).Fn.return_type.?;
                const VOpt = @typeInfo(@TypeOf(T.get)).Fn.return_type.?;
                const K = @typeInfo(KOpt).Optional.child;
                const V = @typeInfo(VOpt).Optional.child;

                const count: usize = value.count();
                try saveTag(TWriter, writer, .Map, count * 2);
                var iter = value.iterator();
                while (iter.next()) |entry| {
                    try save(TWriter, writer, K, entry.key_ptr);
                    try save(TWriter, writer, V, entry.value_ptr);
                }
            } else {
                log.err("save: Unhandled struct type {any}", .{@TypeOf(value)});
                return error.UnhandledType;
            }
        },

        else => {
            log.err("save: Unhandled type {any}", .{T});
            return error.UnhandledType;
        },
    }
}

const SerialType = enum(u3) {
    // Len = type
    Special = 0,
    // Len = bytes
    String = 1,
    PosInt = 2,
    NegInt = 3,
    // Len = elements
    List = 4,
    Map = 5, // x2, because K, V are separate elements
};
pub fn saveTag(comptime TWriter: type, writer: *TWriter, st: SerialType, len: usize) !void {
    if (len < 0xF) {
        try writer.writeIntLittle(u8, (@intCast(u8, @enumToInt(st)) << 4) | @intCast(u8, @intCast(u4, len)));
    } else {
        try writer.writeIntLittle(u8, (@intCast(u8, @enumToInt(st)) << 4) | 0xF);
        if (len < 0xFA) {
            try writer.writeIntLittle(u8, @intCast(u8, len));
        } else {
            var sublen: usize = 0;
            {
                var rem: usize = len;
                while (rem > 0) {
                    rem >>= 8;
                    sublen += 1;
                }
            }
            sublen = @max(2, sublen);
            const lenbyte = @intCast(u8, 0xFF + 2 - sublen);
            if (lenbyte < 0xFA) {
                return error.LengthTooLong;
            }
            try writer.writeIntLittle(u8, lenbyte);
            for (0..sublen) |i| {
                try writer.writeIntLittle(u8, @truncate(u8, len >> @intCast(u5, 8 * i)));
            }
        }
    }
}

fn saveIntPart(comptime TWriter: type, writer: *TWriter, comptime T: type, value: T, negative: bool) !void {
    // Compute length
    var len: usize = 0;
    {
        var rem = value;
        while (rem > 0) {
            len += 1;
            rem >>= 8;
        }
    }

    // Now serialise it
    try saveTag(TWriter, writer, if (negative) .NegInt else .PosInt, len);
    {
        var rem = value;
        while (rem > 0) {
            try writer.writeIntLittle(u8, @truncate(u8, rem));
            rem >>= 8;
        }
    }
}
