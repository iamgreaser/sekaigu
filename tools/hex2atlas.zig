const std = @import("std");
const log = std.log.scoped(.main);
const Allocator = std.mem.Allocator;

const INCHARMAXWIDTH = 16;
const INCHARHEIGHT = 16;

pub const std_options = struct {
    pub const log_level = .err;
    //pub const log_level = .info;
    //pub const log_level = .debug;
};

// We can potentially use up to 16 layers and use RGBA 4:4:4:4 as our internal format.

// Mapping:
// 00 = Unallocated
// 01 = * INVALID * - temporarily used when allocating space
// 10 = Allocated 0
// 11 = Allocated 1
const XSpan = struct {
    const Self = @This();
    xoffs: u16,
    xlen: u16,
    prevptr: *?*XSpan,
    next: ?*XSpan,
};
var atlas_xspan_heads: []?*XSpan = undefined;

var prev_y_per_size: [INCHARHEIGHT][INCHARMAXWIDTH]usize = [1][INCHARMAXWIDTH]usize{
    [1]usize{0} ** INCHARMAXWIDTH,
} ** INCHARHEIGHT;

var atlas_data: []u8 = undefined;
var atlas_pitch: usize = 0;
var atlas_width: usize = 0;
var atlas_height: usize = 0;
var atlas_layers: usize = 0;

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
var glyphs_were_lost: bool = false;

pub fn main() !void {
    const AllocatorType = std.heap.GeneralPurposeAllocator(.{
        //
    });
    var allocator_state = AllocatorType{
        .backing_allocator = std.heap.page_allocator,
    };
    var allocator = allocator_state.allocator();

    const outpbmfname = std.mem.sliceTo(std.os.argv[1], 0);
    const outrawfname = std.mem.sliceTo(std.os.argv[2], 0);
    const outmapfname = std.mem.sliceTo(std.os.argv[3], 0);
    atlas_width = try std.fmt.parseInt(usize, std.mem.sliceTo(std.os.argv[4], 0), 10);
    atlas_height = try std.fmt.parseInt(usize, std.mem.sliceTo(std.os.argv[5], 0), 10);
    atlas_layers = try std.fmt.parseInt(usize, std.mem.sliceTo(std.os.argv[6], 0), 10);
    log.info("Building pbm=\"{s}\", raw=\"{s}\" map=\"{s}\" , {d} x {d}, {d} layer(s)", .{ outpbmfname, outrawfname, outmapfname, atlas_width, atlas_height, atlas_layers });
    atlas_pitch = @divExact(atlas_width, 8);
    char_entries = @TypeOf(char_entries).init(allocator);
    defer char_entries.clearAndFree();
    empties_8 = @TypeOf(empties_8).init(allocator);
    defer empties_8.clearAndFree();
    empties_16 = @TypeOf(empties_16).init(allocator);
    defer empties_16.clearAndFree();

    // Give this some extra space for overflow
    atlas_data = try allocator.alloc(u8, atlas_pitch * atlas_height * atlas_layers + 4);
    defer allocator.free(atlas_data);
    std.mem.set(u8, atlas_data, 0);
    log.info("Allocated size: {d} bytes x2", .{atlas_data.len});

    atlas_xspan_heads = try allocator.alloc(?*XSpan, atlas_height * atlas_layers);
    defer allocator.free(atlas_xspan_heads);
    std.mem.set(?*XSpan, atlas_xspan_heads, null);
    defer destroyXSpanChains(allocator);
    for (atlas_xspan_heads) |*xspanptr| {
        var firstspan = try allocator.create(XSpan);
        errdefer allocator.destroy(firstspan);
        firstspan.* = XSpan{
            .xoffs = 0,
            .xlen = @intCast(u16, atlas_width),
            .prevptr = xspanptr,
            .next = null,
        };
        xspanptr.* = firstspan;
    }

    // Load our glyphs
    for (std.os.argv[7..]) |infname| {
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
        log.debug("Parsing {d}/{d} (-{d}): {x}, origin {d}, {d}, size {d} x {d}", .{ charsdone, i, i - charsdone, ce.char_idx, ce.dstxoffs, ce.dstyoffs, ce.xsize_m1 + 1, ce.ysize_m1 + 1 });
        insertCharData(allocator, ce) catch |err| switch (err) {
            error.CharacterDidNotFit => {
                log.err("Failed to allocate character {x} in atlas", .{ce.char_idx});
                glyphs_were_lost = true;
                lastbadxsize_m1 = ce.xsize_m1;
                lastbadysize_m1 = ce.ysize_m1;
                continue :charInputs;
            },
            else => {
                return err;
            },
        };
        charsdone += 1;
    }

    // Generate sample image
    if (outpbmfname.len >= 1) {
        log.info("Saving PBM sample image output \"{s}\"", .{outpbmfname});
        const file = try std.fs.cwd().createFile(outpbmfname, .{
            .read = false,
            .truncate = true,
        });
        defer file.close();
        const writer = file.writer();
        try writer.print("P4 {d} {d}\n", .{ atlas_width, atlas_height * atlas_layers });
        try writer.writeAll(atlas_data);
    }

    // Generate raw image
    if (outrawfname.len >= 1) {
        const BUFSIZE = 1024 * 16;
        log.info("Saving raw RGBA4444 image output \"{s}\"", .{outrawfname});
        const file = try std.fs.cwd().createFile(outrawfname, .{
            .read = false,
            .truncate = true,
        });
        defer file.close();
        var block = try allocator.alloc(u8, atlas_width * 2);
        defer allocator.free(block);
        std.mem.set(u8, block, 0);

        const raw_writer = file.writer();
        var buffered_writer_state = std.io.BufferedWriter(BUFSIZE, @TypeOf(raw_writer)){
            .unbuffered_writer = raw_writer,
        };
        var buffered_writer = buffered_writer_state.writer();
        var deflate_compressor = try std.compress.deflate.compressor(allocator, buffered_writer, .{});
        defer deflate_compressor.deinit();
        var writer = deflate_compressor.writer();
        // First component starts at the MSbit
        const layer_remap = [_]u16{
            0x8000, 0x0800, 0x0080, 0x0008,
            0x4000, 0x0400, 0x0040, 0x0004,
            0x2000, 0x0200, 0x0020, 0x0002,
            0x1000, 0x0100, 0x0010, 0x0001,
        };
        for (0..atlas_height) |cy| {
            for (0..atlas_width) |cx| {
                var v: u16 = 0;
                for (0..atlas_layers) |cl| {
                    const pmask = atlas_data[((cl * atlas_layers) + cy) * atlas_width + (cx >> 3)];
                    if (((pmask << @truncate(u3, cx)) & 0x80) != 0)
                        v |= layer_remap[cl];
                }
                inline for (0..2) |shifti| {
                    block[2 * cx + shifti] = @truncate(u8, v >> (shifti * 8));
                }
            }
            try writer.writeAll(block);
        }
    }

    // Remove what isn't in there
    {
        log.info("Removing missing chars", .{});
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
    log.info("Sorting glyphs by ascending char index", .{});
    std.sort.sort(CharEntry, char_entries.items, {}, CharEntry.codepointLessThan);

    // Generate map file
    if (outmapfname.len >= 1) {
        const BUFSIZE = 1024 * 16;
        log.info("Saving map output \"{s}\"", .{outmapfname});
        const file = try std.fs.cwd().createFile(outmapfname, .{
            .read = false,
            .truncate = true,
        });
        defer file.close();
        const raw_writer = file.writer();
        var buffered_writer_state = std.io.BufferedWriter(BUFSIZE, @TypeOf(raw_writer)){
            .unbuffered_writer = raw_writer,
        };
        var buffered_writer = buffered_writer_state.writer();
        var deflate_compressor = try std.compress.deflate.compressor(allocator, buffered_writer, .{});
        defer deflate_compressor.deinit();
        var writer = deflate_compressor.writer();
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
        try deflate_compressor.close();
        try buffered_writer_state.flush();
    }

    log.info("Done", .{});
    if (glyphs_were_lost) {
        log.err("Glyphs were lost, exiting with an error", .{});
        std.process.exit(1);
    }
}

fn destroyXSpanChains(allocator: Allocator) void {
    for (atlas_xspan_heads) |*xsp| {
        while (xsp.*) |xspan| {
            xsp.* = xspan.next;
            allocator.destroy(xspan);
        }
    }
}

fn appendFilenameToAtlas(fname: []const u8) !void {
    // TODO! --GM
    log.info("Adding \"{s}\" to atlas", .{fname});
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
        log.debug("Char {x} is blank, width = {d}", .{ char_idx, RowLen * 4 });
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

pub fn insertCharData(allocator: Allocator, ce: *CharEntry) !void {
    const charbuf: []const u32 = &ce.charbuf;
    const char_idx = ce.char_idx;
    const xlen: usize = ce.xsize_m1 + 1;
    const ylen: usize = ce.ysize_m1 + 1;
    //const xmask: u32 = 0 -% (@as(u32, 0x80000000) >> @intCast(u5, xlen - 1));

    // Now scan the entire atlas for an empty space
    var bestx: usize = 0;
    var besty: usize = 0;
    var bestl: usize = 0;
    var spanlistbuf: [INCHARHEIGHT]*XSpan = undefined;
    foundSpace: {
        for (0..atlas_layers) |cl| {
            const loffs: usize = cl * atlas_height;
            const firsty = @max(prev_y_per_size[ylen - 1][xlen - 1], loffs + 0);
            const lasty = loffs + atlas_height - ylen;
            if (firsty < lasty) {
                for (firsty..lasty) |cy| {
                    var xprevpp = &atlas_xspan_heads[cy];
                    var xsp = xprevpp.*;
                    while (xsp) |xspan| {
                        const firstx = xspan.xoffs;
                        if (xspan.xoffs + xspan.xlen >= xlen and firstx < xspan.xoffs + xspan.xlen - xlen) {
                            const lastx = xspan.xoffs + xspan.xlen - xlen;
                            for (firstx..lastx) |cx| {
                                posFail: {
                                    spanlistbuf[0] = xspan;
                                    // Find span in this place
                                    nextY: for (1..ylen) |sy| {
                                        var subwalk: ?*XSpan = atlas_xspan_heads[cy + sy];
                                        while (subwalk) |subspan| {
                                            // TODO! --GM
                                            //log.debug("subwalk {d} {d} {d} {*}", .{ cx, cy, sy, subspan });
                                            if (subspan.xoffs <= cx and cx + xlen <= subspan.xoffs + subspan.xlen) {
                                                spanlistbuf[sy] = subspan;
                                                continue :nextY;
                                            }
                                            subwalk = subspan.*.next;
                                        }
                                        break :posFail;
                                    }
                                    bestx = cx;
                                    besty = cy;
                                    bestl = cl;
                                    break :foundSpace;
                                }
                            }
                        }
                        xsp = xspan.next;
                    }
                }
            }
        }

        // If we failed to allocate, throw an error
        return error.CharacterDidNotFit;
    }

    // Now actually allocate the character
    log.debug("Allocated {x}, pos {d}, {d}", .{ char_idx, bestx, besty });
    prev_y_per_size[ylen - 1][xlen - 1] = besty;
    for (0..ylen) |sy| {
        const tx = bestx;
        const ty = besty + sy;
        try allocXSpan(allocator, spanlistbuf[sy], @intCast(u16, bestx), @intCast(u16, xlen));
        const aoffs = (ty * atlas_pitch) + (tx >> 3);
        const cshift: u5 = @intCast(u5, tx & 0b111);
        const sv = charbuf[sy] >> cshift;
        inline for (0..3) |i| {
            const ishift: u5 = (24 - (8 * i));
            const bv: u8 = @truncate(u8, sv >> ishift);
            atlas_data[aoffs + i] |= bv;
        }
    }

    //log.debug("{any}", .{atlas_first_empty_y});
    ce.srcxoffs = @intCast(u16, bestx);
    ce.srcyoffs = @intCast(u16, besty);
}

fn allocXSpan(allocator: Allocator, xspan: *XSpan, xoffs: u16, xlen: u16) !void {
    // Split into our different cases
    if (xspan.xoffs == xoffs) {
        // Fully against left
        if (xspan.xlen != xlen) {
            // Not fully against right
            xspan.xoffs += xlen;
            xspan.xlen -= xlen;
        } else {
            // Fully against right
            if (xspan.next) |next| {
                next.prevptr = xspan.prevptr;
            }
            xspan.prevptr.* = xspan.next;
            allocator.destroy(xspan);
        }
    } else {
        // Not butted against left
        if (xoffs + xlen != xspan.xoffs + xspan.xlen) {
            // Not fully against right
            var newspan = try allocator.create(XSpan);
            errdefer allocator.destroy(newspan);
            newspan.next = xspan.next;
            newspan.prevptr = &(xspan.next);
            newspan.xoffs = xoffs + xlen;
            newspan.xlen = xspan.xoffs + xspan.xlen - newspan.xoffs;
            xspan.xlen = xoffs - xspan.xoffs;
            xspan.next = newspan;
        } else {
            // Fully against right
            // WARNING: UNTESTED!
            xspan.xlen -= xlen;
        }
    }
}
