const std = @import("std");
const log = std.log.scoped(.webserver_request);
const http = std.http;

const http_types = @import("http_types.zig");
const ConnectionType = http_types.ConnectionType;

pub fn Response(comptime Parent: type) type {
    _ = Parent;
    return struct {
        const Self = @This();
        status: http.Status,
        body_buf: ?[]const u8,
        headers: struct {
            @"Content-Type": ?[]const u8 = null,
            @"Content-Length": ?usize = null,
            Location: ?[]const u8 = null,
            Connection: ?ConnectionType = .close,
        } = .{},
        header_idx: usize = 0,
        body_written: usize = 0,

        state: enum(u8) {
            WriteCommand,
            WriteHeaders,
            WriteBody,
            WriteFlushClose,
            Done,
        } = .WriteCommand,
    };
}
