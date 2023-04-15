const std = @import("std");
const log = std.log.scoped(.webserver_request);
const http = std.http;

pub const PATH_BUF_SIZE = 64;

const http_types = @import("http_types.zig");
const ConnectionType = http_types.ConnectionType;

pub fn Request(comptime Parent: type) type {
    _ = Parent;
    return struct {
        const Self = @This();
        method: ?http.Method = null,
        headers: struct {
            Connection: ?ConnectionType = .close,
        } = .{},
        path_buf: [PATH_BUF_SIZE]u8 = undefined,
        path: ?[]u8 = null,
    };
}
