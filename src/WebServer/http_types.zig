const std = @import("std");
const log = std.log.scoped(.webserver_types);
const http = std.http;

pub const PATH_BUF_SIZE = 64;

pub const ConnectionType = enum {
    close,
    // Both capitalisations are a thing and it's stupid and ill-defined. --GM
    @"Keep-Alive",
    @"keep-alive",
};

pub const Request = struct {
    const Self = @This();
    method: ?http.Method = null,
    headers: struct {
        Connection: ?ConnectionType = .close,
    } = .{},
    path_buf: [PATH_BUF_SIZE]u8 = undefined,
    path: ?[]u8 = null,
};
pub const Response = struct {
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
};
