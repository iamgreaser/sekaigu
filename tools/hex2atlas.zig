const std = @import("std");
const log = std.log.scoped(.main);

const INCHARHEIGHT = 16;

// We can potentially use up to 16 layers and use RGBA 4:4:4:4 as our internal format.

// Mapping:
// 00 = Unallocated
// 01 = * INVALID * - temporarily used when allocating space
// 10 = Allocated 0
// 11 = Allocated 1
var atlas_usedmask: []u8 = undefined;
var atlas_data: []u8 = undefined;
var atlas_pitch: usize = 0;
var atlas_width: usize = 0;
var atlas_height: usize = 0;
var atlas_layers: usize = 0;
var atlas_first_empty_x: []usize = undefined;

const CharEntry = struct {
    char_idx: u32,
    srcxoffs: u16,
    srcyoffs: u16,
    dstxoffs: u8,
    dstyoffs: u8,
    xsize_m1: u8,
    ysize_m1: u8,
    charbuf: [INCHARHEIGHT]u32,

    const Self = @This();

    pub fn area(self: Self) usize {
        return @intCast(usize, self.xsize_m1 + 1) * @intCast(usize, self.ysize_m1 + 1);
    }

    pub fn codepointLessThan(_: void, a: Self, b: Self) bool {
        return a.char_idx < b.char_idx;
    }

    pub fn sizeGoesEarlier(_: void, a: Self, b: Self) bool {
        //return a.area() > b.area();
        return a.xsize_m1 > b.xsize_m1 or (a.xsize_m1 == b.xsize_m1 and a.ysize_m1 > b.ysize_m1);
    }
};
var char_entries: std.ArrayList(CharEntry) = undefined;
var empties_8: std.ArrayList(u21) = undefined;
var empties_16: std.ArrayList(u21) = undefined;

pub fn main() !void {
    const AllocatorType = std.heap.GeneralPurposeAllocator(.{
        //
    });
    var allocator_state = AllocatorType{
        .backing_allocator = std.heap.page_allocator,
    };
    var allocator = allocator_state.allocator();

    const outimgfname = std.mem.sliceTo(std.os.argv[1], 0);
    const outmapfname = std.mem.sliceTo(std.os.argv[2], 0);
    atlas_width = try std.fmt.parseInt(usize, std.mem.sliceTo(std.os.argv[3], 0), 10);
    atlas_height = try std.fmt.parseInt(usize, std.mem.sliceTo(std.os.argv[4], 0), 10);
    atlas_layers = try std.fmt.parseInt(usize, std.mem.sliceTo(std.os.argv[5], 0), 10);
    log.err("Building img=\"{s}\", map=\"{s}\" , {d} x {d}, {d} layer(s)", .{ outimgfname, outmapfname, atlas_width, atlas_height, atlas_layers });
    atlas_pitch = @divExact(atlas_width, 8);
    char_entries = @TypeOf(char_entries).init(allocator);
    defer char_entries.clearAndFree();
    empties_8 = @TypeOf(empties_8).init(allocator);
    defer empties_8.clearAndFree();
    empties_16 = @TypeOf(empties_16).init(allocator);
    defer empties_16.clearAndFree();

    // Give this some extra space for overflow
    atlas_usedmask = try allocator.alloc(u8, atlas_pitch * atlas_height * atlas_layers + 4);
    defer allocator.free(atlas_usedmask);
    std.mem.set(u8, atlas_usedmask, 0);
    atlas_data = try allocator.alloc(u8, atlas_pitch * atlas_height * atlas_layers + 4);
    defer allocator.free(atlas_data);
    std.mem.set(u8, atlas_data, 0);
    log.err("Allocated size: {d} bytes x2", .{atlas_usedmask.len});
    atlas_first_empty_x = try allocator.alloc(usize, atlas_height * atlas_layers);
    defer allocator.free(atlas_first_empty_x);
    std.mem.set(usize, atlas_first_empty_x, 0);

    // Load our glyphs
    for (std.os.argv[6..]) |infname| {
        try appendFilenameToAtlas(std.mem.sliceTo(infname, 0));
    }

    // Sort glyphs by size
    std.sort.sort(CharEntry, char_entries.items, {}, CharEntry.sizeGoesEarlier);

    // Generate our atlas
    var charsdone: usize = 0;
    var lastbadxsize_m1: u8 = 17 - 1;
    var lastbadysize_m1: u8 = 17 - 1;
    charInputs: for (char_entries.items, 0..) |*ce, i| {
        if (ce.xsize_m1 == lastbadxsize_m1 and ce.ysize_m1 == lastbadysize_m1) {
            continue :charInputs;
        }
        log.err("Parsing {d}/{d} (-{d}): {x}, origin {d}, {d}, size {d} x {d}", .{ charsdone, i, i - charsdone, ce.char_idx, ce.dstxoffs, ce.dstyoffs, ce.xsize_m1 + 1, ce.ysize_m1 + 1 });
        insertCharData(ce) catch |err| switch (err) {
            error.CharacterDidNotFit => {
                log.err("Failed to allocate character in atlas", .{});
                lastbadxsize_m1 = ce.xsize_m1;
                lastbadysize_m1 = ce.ysize_m1;
                continue :charInputs;
            },
            //else => { return err; },
        };
        charsdone += 1;
    }

    // Generate atlas texture file
    {
        log.err("Saving image output \"{s}\"", .{outimgfname});
        const file = try std.fs.cwd().createFile(outimgfname, .{
            .read = false,
            .truncate = true,
        });
        defer file.close();
        const writer = file.writer();
        try writer.print("P4 {d} {d}\n", .{ atlas_width, atlas_height * atlas_layers });
        try writer.writeAll(atlas_data);
    }

    // Remove what isn't in there
    {
        log.err("Removing missing chars", .{});
        var i: usize = 0;
        while (i < char_entries.items.len) {
            const ce = &char_entries.items[i];
            if (ce.srcxoffs >= atlas_width) {
                _ = char_entries.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    // Sort it again
    log.err("Sorting glyphs by ascending char index", .{});
    std.sort.sort(CharEntry, char_entries.items, {}, CharEntry.codepointLessThan);

    // Generate map file
    {
        log.err("Saving map output \"{s}\"", .{outmapfname});
        const file = try std.fs.cwd().createFile(outmapfname, .{
            .read = false,
            .truncate = true,
        });
        defer file.close();
        const writer = file.writer();
        try writer.writeIntLittle(u32, @intCast(u32, empties_8.items.len));
        try writer.writeIntLittle(u32, @intCast(u32, empties_16.items.len));
        try writer.writeIntLittle(u32, @intCast(u32, char_entries.items.len));
        for (empties_8.items) |v| {
            try writer.writeIntLittle(u32, v);
        }
        for (empties_16.items) |v| {
            try writer.writeIntLittle(u32, v);
        }
        for (char_entries.items) |ce| {
            try writer.writeIntLittle(u32, ce.char_idx);
            try writer.writeIntLittle(u16, ce.srcxoffs);
            try writer.writeIntLittle(u16, ce.srcyoffs);
            try writer.writeIntLittle(u8, ce.dstxoffs);
            try writer.writeIntLittle(u8, ce.dstyoffs);
            try writer.writeIntLittle(u8, ce.xsize_m1);
            try writer.writeIntLittle(u8, ce.xsize_m1);
        }
    }

    log.err("Done", .{});
}

fn appendFilenameToAtlas(fname: []const u8) !void {
    // TODO! --GM
    log.err("Adding \"{s}\" to atlas", .{fname});
    {
        const file = try std.fs.cwd().openFile(fname, .{ .mode = .read_only });
        defer file.close();
        try appendFileToAtlas(file);
    }
}

fn appendFileToAtlas(file: std.fs.File) !void {
    const BUFSIZE = 1024 * 16;
    var raw_reader = file.reader();
    var buffered_reader_state = std.io.BufferedReader(BUFSIZE, @TypeOf(raw_reader)){
        .unbuffered_reader = raw_reader,
    };
    var reader = buffered_reader_state.reader();

    // Read lines
    done: while (true) {
        var linebuf: [1024]u8 = undefined;
        const line = reader.readUntilDelimiter(&linebuf, '\n') catch |err| switch (err) {
            error.EndOfStream => break :done,
            else => return err,
        };
        const delim_sep0 = std.mem.indexOfScalar(u8, line, ':') orelse {
            return error.InvalidFormat;
        };
        const char_str = line[delim_sep0 + 1 ..];
        const char_idx = try std.fmt.parseInt(u21, line[0..delim_sep0], 16);

        // Load character glyph data
        switch (char_str.len) {
            16 * 2 * 1 => try parseCharData(2, char_idx, char_str),
            16 * 2 * 2 => try parseCharData(4, char_idx, char_str),
            else => {
                return error.InvalidFormat;
            },
        }
    }
}

pub fn parseCharData(comptime RowLen: comptime_int, char_idx: u21, char_str: []const u8) !void {
    var incharbuf = [1]u32{0} ** INCHARHEIGHT;
    var ymin: usize = 15;
    var ymax: usize = 0;
    var xmin: usize = RowLen * 4 - 1;
    var xmax: usize = 0;
    for (0..16) |y| {
        const row: u32 = try std.fmt.parseInt(u32, char_str[RowLen * y ..][0..RowLen], 16);
        incharbuf[y] = row << (32 - (RowLen * 4));
        for (0..RowLen * 4) |x| {
            if (@bitCast(i32, incharbuf[y] << @intCast(u5, x)) < 0) {
                xmin = @min(xmin, x);
                xmax = @max(xmax, x);
                ymin = @min(ymin, y);
                ymax = @max(ymax, y);
            }
        }
    }

    // If the character is completely blank, mark it as such and skip
    if (xmax < xmin) {
        log.err("Char {x} is blank, width = {d}", .{ char_idx, RowLen * 4 });
        switch (RowLen) {
            2 => try empties_8.append(char_idx),
            4 => try empties_16.append(char_idx),
            else => unreachable,
        }
        return;
    }

    const xoffs = xmin;
    const yoffs = ymin;
    const xlen = xmax + 1 - xmin;
    const ylen = ymax + 1 - ymin;
    for (0..ylen) |y| {
        incharbuf[y] = incharbuf[y + yoffs] << @intCast(u5, xoffs);
    }

    try char_entries.append(CharEntry{
        .char_idx = char_idx,
        .srcxoffs = @intCast(u16, atlas_width),
        .srcyoffs = @intCast(u16, atlas_height * atlas_layers),
        .dstxoffs = @intCast(u8, xoffs),
        .dstyoffs = @intCast(u8, yoffs),
        .xsize_m1 = @intCast(u8, xlen - 1),
        .ysize_m1 = @intCast(u8, ylen - 1),
        .charbuf = incharbuf,
    });
}

pub fn insertCharData(ce: *CharEntry) !void {
    const charbuf: []const u32 = &ce.charbuf;
    const char_idx = ce.char_idx;
    const xlen: usize = ce.xsize_m1 + 1;
    const ylen: usize = ce.ysize_m1 + 1;
    const xmask: u32 = 0 -% (@as(u32, 0x80000000) >> @intCast(u5, xlen - 1));

    // Now scan the entire atlas for an empty space
    var bestx: usize = 0;
    var besty: usize = 0;
    var bestl: usize = 0;
    foundSpace: {
        for (0..atlas_layers) |cl| {
            const loffs: usize = cl * atlas_height;
            const lasty = loffs + atlas_height - ylen;
            for (loffs + 0..lasty) |cy| {
                const firstx = atlas_first_empty_x[cy];
                const lastx = atlas_width - xlen;
                if (firstx < lastx) {
                    for (firstx..lastx) |cx| {
                        const inshift: u5 = @intCast(u5, cx & 0b111);
                        const cmask = xmask >> inshift;
                        posFail: {
                            const aoffs_base = (cy * atlas_pitch) + (cx >> 3);
                            for (0..ylen) |sy| {
                                const aoffs = aoffs_base + (sy * atlas_pitch);
                                const am: u32 = (@as(u32, atlas_usedmask[aoffs + 0]) << 24) | (@as(u32, atlas_usedmask[aoffs + 1]) << 16) | (@as(u32, atlas_usedmask[aoffs + 2]) << 8);
                                if ((am & cmask) != 0) {
                                    break :posFail;
                                }
                            }
                            bestx = cx;
                            besty = cy;
                            bestl = cl;
                            break :foundSpace;
                        }
                    }
                }
            }
        }

        // If we failed to allocate, throw an error
        return error.CharacterDidNotFit;
    }

    // Now actually allocate the character
    log.err("Allocated {x}, pos {d}, {d}", .{ char_idx, bestx, besty });
    for (0..ylen) |sy| {
        const tx = bestx;
        const ty = besty + sy;
        const aoffs = (ty * atlas_pitch) + (tx >> 3);
        const cshift: u5 = @intCast(u5, tx & 0b111);
        const sm = xmask >> cshift;
        const sv = charbuf[sy] >> cshift;
        inline for (0..3) |i| {
            const ishift: u5 = (24 - (8 * i));
            const bm: u8 = @truncate(u8, sm >> ishift);
            const bv: u8 = @truncate(u8, sv >> ishift);
            atlas_usedmask[aoffs + i] |= bm;
            atlas_data[aoffs + i] |= bv;
        }
        xLeftWipe: for (atlas_first_empty_x[ty]..atlas_width) |cx| {
            const xaoffs = (ty * atlas_pitch) + (cx >> 3);
            const xam = atlas_usedmask[xaoffs];
            if ((xam & (@as(u8, 0x80) >> @intCast(u3, cx & 0b111))) != 0) {
                atlas_first_empty_x[ty] = cx + 1;
            } else {
                break :xLeftWipe;
            }
        }
    }
    ce.srcxoffs = @intCast(u16, bestx);
    ce.srcyoffs = @intCast(u16, besty);
}
