const std = @import("std");
const log = std.log.scoped(.main);

const USEPADDING = false;

const PADDING = if (USEPADDING) 1 else 0;
const INCHARPITCH = 16 + (PADDING * 2); // (RowLen * 4) + padding;
const INCHARHEIGHT = 16 + (PADDING * 2); // 16 + padding;

// We can potentially use up to 16 layers and use RGBA 4:4:4:4 as our internal format.

// Mapping:
// 00 = Unallocated
// 01 = * INVALID * - temporarily used when allocating space
// 10 = Allocated 0
// 11 = Allocated 1
var outatlas: []u2 = undefined;
var atlas_width: usize = 0;
var atlas_height: usize = 0;
var atlas_layers: usize = 0;

const CharEntry = packed struct {
    char_idx: u32,
    srcxoffs: u16,
    srcyoffs: u16,
    dstxoffs: u8,
    dstyoffs: u8,
    xsize_m1: u8,
    ysize_m1: u8,
};
var char_entries: std.ArrayList(CharEntry) = undefined;

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
    log.info("Building img=\"{s}\", map=\"{s}\" , {d} x {d}, {d} layer(s)", .{ outimgfname, outmapfname, atlas_width, atlas_height, atlas_layers });
    char_entries = @TypeOf(char_entries).init(allocator);

    // NOTE: []u2 uses a whole byte per element
    outatlas = try allocator.alloc(u2, atlas_width * atlas_height * atlas_layers);
    defer allocator.free(outatlas);
    std.mem.set(u2, outatlas, 0);
    var packedatlas: []u8 = try allocator.alloc(u8, @divExact(atlas_width, 8) * atlas_height * atlas_layers);
    defer allocator.free(packedatlas);
    log.info("Allocated size: {d} bytes", .{outatlas.len});
    //log.info("byte diff test {d}", .{@ptrToInt(&outfield[21]) - @ptrToInt(&outfield[0])});

    // Create our atlas
    doneInputs: for (std.os.argv[6..]) |infname| {
        appendFilenameToAtlas(std.mem.sliceTo(infname, 0)) catch |err| switch (err) {
            error.CharacterDidNotFit => {
                log.err("Failed to allocate character in atlas - let's see what's in the atlas at the very least", .{});
                break :doneInputs;
            },
            else => {
                return err;
            },
        };
    }

    // Pack atlas image
    for (0..(atlas_height * atlas_layers)) |y| {
        for (0..@divExact(atlas_width, 8)) |x| {
            var v: u8 = 0;
            const src = outatlas[(y * atlas_width) + (x * 8) ..][0..8];
            for (0..8) |sx| {
                if (src[sx] == 0b11) {
                    v |= @as(u8, 0x80) >> @intCast(u3, sx);
                }
            }
            packedatlas[y * @divExact(atlas_width, 8) + x] = v;
        }
    }

    // Generate atlas texture file
    {
        log.info("Saving image output \"{s}\"", .{outimgfname});
        const file = try std.fs.cwd().createFile(outimgfname, .{
            .read = false,
            .truncate = true,
        });
        defer file.close();
        const writer = file.writer();
        try writer.print("P4 {d} {d}\n", .{ atlas_width, atlas_height * atlas_layers });
        try writer.writeAll(packedatlas);
    }

    log.info("Done", .{});
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
            16 * 2 * 1 => try parseCharData(u8, 2, char_idx, char_str),
            16 * 2 * 2 => try parseCharData(u16, 4, char_idx, char_str),
            else => {
                return error.InvalidFormat;
            },
        }
        // Find a spot in the atlas for this to go
        //log.info("Line: {x} {d} {s}", .{ char_idx, @divExact(char_data.len, 2 * 16), char_data });
        //log.info("Line: {x} {any}", .{ char_idx, char_data });
        //_ = char_data;

        // TODO: Emit char index + dims --GM
    }
}

pub fn parseCharData(comptime Uint: type, comptime RowLen: comptime_int, char_idx: u21, char_str: []const u8) !void {
    // NOTE: We have 1-pixel-wide padding on the leftmost, topmost, rightmost and bottommost pixel rows/columns.
    const UintShift = switch (Uint) {
        u8 => u3,
        u16 => u4,
        else => unreachable,
    };
    var charbuf = [1]u2{0} ** (INCHARHEIGHT * INCHARPITCH);
    var ymin: usize = 15;
    var ymax: usize = 0;
    var xmin: usize = RowLen * 4 - 1;
    var xmax: usize = 0;
    for (0..16) |y| {
        const row = try std.fmt.parseInt(Uint, char_str[RowLen * y ..][0..RowLen], 16);
        for (0..RowLen * 4) |x| {
            const v = @intCast(u2, (row >> @intCast(UintShift, (RowLen * 4 - 1 - x))) & 0b1);
            charbuf[((y + PADDING) * INCHARPITCH) + (x + PADDING)] = v | 0b10;
            if (v != 0) {
                xmin = @min(xmin, x);
                xmax = @max(xmax, x);
                ymin = @min(ymin, y);
                ymax = @max(ymax, y);
            }
        }
    }

    // If the character is completely blank, mark it as such and skip
    if (xmax < xmin) {
        // TODO: Actually mark characters as such --GM
        log.info("Char {x} is blank, width = {d}", .{ char_idx, RowLen * 4 });
        return;
    }

    log.err("Parsing {d}: {x}, origin {d}, {d}, size {d} x {d}", .{ char_entries.items.len, char_idx, xmin, ymin, xmax + 1 - xmin, ymax + 1 - ymin });

    var bestoverlap: isize = -1;
    var bestx: usize = 0;
    var besty: usize = 0;
    const xoffs = xmin;
    const yoffs = ymin;
    const poffs = (INCHARPITCH * yoffs) + xoffs;
    const xlen = xmax + 1 - xmin + (PADDING * 2);
    const ylen = ymax + 1 - ymin + (PADDING * 2);

    // Now scan the entire atlas to see if we can overlap with what's there
    skipRestOfAtlas: for (0..atlas_layers) |cl| {
        const loffs = cl * atlas_height;
        for (loffs + 0..loffs + atlas_height - ylen) |cy| {
            skipRestOfRow: for (0..atlas_width - xlen) |cx| {
                posFail: {
                    var thisoverlap: isize = 0;
                    for (0..ylen) |sy| {
                        for (0..xlen) |sx| {
                            // TODO!
                            const tx = cx + sx;
                            const ty = cy + sy;
                            const av = outatlas[(ty * atlas_width) + tx];
                            const sv = charbuf[poffs + (INCHARPITCH * sy) + sx];
                            if (av != 0) {
                                if (sv == av) {
                                    thisoverlap += 1;
                                } else {
                                    break :posFail;
                                }
                            }
                        }
                    }
                    if (thisoverlap > bestoverlap) {
                        bestoverlap = thisoverlap;
                        bestx = cx;
                        besty = cy;
                    }
                    // FLAWED OPTIMISATION: If this is a fully empty spot, skip the rest of this row.
                    if (thisoverlap == 0) {
                        if (cx == 0) {
                            break :skipRestOfAtlas;
                        }
                        break :skipRestOfRow;
                    }
                }
            }
        }
    }

    // If we failed to allocate, throw an error
    if (bestoverlap < 0) {
        return error.CharacterDidNotFit;
    }

    // Now actually allocate the character
    log.err("Allocated {x}, pos {d}, {d}, overlap {d}/{d}", .{ char_idx, bestx, besty, bestoverlap, xlen * ylen });
    for (0..ylen) |sy| {
        for (0..xlen) |sx| {
            const tx = bestx + sx;
            const ty = besty + sy;
            const sv = charbuf[poffs + (INCHARPITCH * sy) + sx];
            outatlas[(ty * atlas_width) + tx] = sv;
        }
    }

    try char_entries.append(CharEntry{
        .char_idx = char_idx,
        .srcxoffs = @intCast(u16, bestx),
        .srcyoffs = @intCast(u16, besty),
        .dstxoffs = @intCast(u8, xoffs),
        .dstyoffs = @intCast(u8, yoffs),
        .xsize_m1 = @intCast(u8, xlen - (PADDING * 2) - 1),
        .ysize_m1 = @intCast(u8, ylen - (PADDING * 2) - 1),
    });
}
