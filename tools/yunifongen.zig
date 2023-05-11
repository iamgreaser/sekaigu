// SPDX-License-Identifier: AGPL-3.0-or-later
// Input font: "GNU Unifont 15.0.01", licensed under SIL OFL v1.1
// Output font: "sekaigu yunifon JP 15.0.01.0", licensed under SIL OFL v1.1

const std = @import("std");
const log = std.log.scoped(.main);
const mem = std.mem;
const Allocator = std.mem.Allocator;

const INCHARMAXWIDTH = 16;
const INCHARHEIGHT = 16;

pub const std_options = struct {
    //pub const log_level = .err;
    //pub const log_level = .info;
    pub const log_level = .debug;
};

var glyphmap: std.AutoHashMap(u21, []u8) = undefined;

// WARNING: A FixedBufferAllocator can ONLY free the last block!
// If you free anything else, then that and everything before that is PERMANENTLY LEAKED!
// (andrewrk mentioned on IRC that they were thinking of renaming this allocator to BumpAllocator)
// Because of this, we're setting this buffer to at least as long as it needs to be. --GM
//
// 10 MB static allocation for fixed buffer allocator
// (because 9 MB is too small for what we want --GM)
var fba_backing: [1024 * 1024 * 10]u8 = undefined;

pub fn main() !void {
    // If detecting leaks, go via GeneralPurposeAllocator.
    // Otherwise, hammer a FixedBufferAllocator.
    //var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    //defer _ = gpa.deinit();
    //const allocator = gpa.allocator();

    var fba = std.heap.FixedBufferAllocator.init(&fba_backing);
    const allocator = fba.allocator();

    glyphmap = @TypeOf(glyphmap).init(allocator);
    defer ({
        var iter = glyphmap.valueIterator();
        while (iter.next()) |v| allocator.free(v.*);
        glyphmap.deinit();
    });

    const outhexfname = std.mem.sliceTo(std.os.argv[1], 0);

    // Load our glyphs
    for (std.os.argv[2..]) |infname| {
        log.info("Loading glyphs from \"{s}\"", .{infname});
        try loadGlyphs(allocator, std.mem.sliceTo(infname, 0));
    }

    // Save our glyphs
    {
        log.info("Saving glyphs to \"{s}\"", .{outhexfname});
        const BUFSIZE = 1024 * 16;
        const file = try std.fs.cwd().createFile(outhexfname, .{
            .read = false,
            .truncate = true,
        });
        defer file.close();
        const raw_writer = file.writer();
        var buffered_writer_state = std.io.BufferedWriter(BUFSIZE, @TypeOf(raw_writer)){
            .unbuffered_writer = raw_writer,
        };
        var writer = buffered_writer_state.writer();

        for (0..0x10FFFF + 1) |idx| {
            if (glyphmap.get(@intCast(u21, idx))) |data| {
                //log.debug("Glyph {X:0>6}", .{idx});
                try writer.print("{X:0>6}:{s}\n", .{ idx, data });
            }
        }

        try buffered_writer_state.flush();
    }

    log.info("Done!", .{});
}

pub fn loadGlyphs(allocator: Allocator, infname: []const u8) !void {
    const file = try std.fs.cwd().openFile(infname, .{ .mode = .read_only });
    defer file.close();
    var reader_backing = std.io.bufferedReader(file.reader());
    const reader = reader_backing.reader();

    // Read a glyph if possible
    // Buffer size: max(index, charsize) + 1 (needs to include delimiter)
    // WARNING: *MUST* use LF newlines! (no CRLF, definitely no CR)
    var readbuf: [@max(6, INCHARHEIGHT * 2 * ((INCHARMAXWIDTH + 7) >> 3)) + 1]u8 = undefined;
    lineLoop: while (try reader.readUntilDelimiterOrEof(&readbuf, ':')) |idxstr| {
        if (idxstr.len == 0) continue :lineLoop;
        var idx: u21 = try std.fmt.parseInt(u21, idxstr, 16);
        const optdatastr = (try reader.readUntilDelimiterOrEof(&readbuf, '\n'));
        const datastr = (optdatastr orelse {
            log.err("expected glyph data, found EOF instead", .{});
            return error.UnexpectedEof;
        });
        //log.debug("loading glyph {X:0>6}, len = {d:>3}", .{ idx, datastr.len });
        switch (datastr.len) {
            INCHARHEIGHT * 2 * 1 => {},
            INCHARHEIGHT * 2 * 2 => {},
            else => {
                log.err("invalid glyph size", .{});
                return error.InvalidGlyphSize;
            },
        }
        if (!glyphmap.contains(idx)) {
            var outstr = try allocator.dupe(u8, datastr);
            errdefer allocator.free(outstr);
            try glyphmap.putNoClobber(idx, outstr);
            errdefer _ = glyphmap.remove(idx);
        }
    }
}
