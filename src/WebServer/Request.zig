const std = @import("std");
const log = std.log.scoped(.webserver_request);
const http = std.http;

pub const PATH_BUF_SIZE = 64;

const http_types = @import("http_types.zig");
const ConnectionType = http_types.ConnectionType;

pub fn Request(comptime Parent: type) type {
    return struct {
        const Self = @This();
        parent: *Parent,
        method: ?http.Method = null,
        headers: struct {
            Connection: ?ConnectionType = .close,
        } = .{},
        path_buf: [PATH_BUF_SIZE]u8 = undefined,
        path: ?[]u8 = null,

        state: enum(u8) {
            ReadCommand,
            ReadHeaders,
            //ReadBody, // Supporting this would make this use more dynamic RAM allocation --GM
            Done,
        } = .ReadCommand,

        pub fn isDone(self: *const Self) bool {
            return self.state == .Done;
        }

        pub fn parseLine(self: *Self, line: []const u8) !bool {
            // TODO! --GM
            log.debug("In Line: {d} <<{s}>>", .{ line.len, line });
            switch (self.state) {
                .ReadCommand => {
                    // COMMAND path HTTP/ver
                    if (std.mem.indexOfPos(u8, line, 0, " ")) |pos0| {
                        if (std.mem.indexOfPos(u8, line, pos0 + 1, " ")) |pos1| {
                            const method = line[0..pos0];
                            const path = line[pos0 + 1 .. pos1];
                            const httpver = line[pos1 + 1 ..];
                            log.debug("Handling method: \"{s}\" path: \"{s}\" ver: \"{s}\"", .{ method, path, httpver });
                            // TODO: Parse HTTP version for conformance to HTTP/1.1 --GM
                            self.method = method: {
                                inline for (@typeInfo(http.Method).Enum.fields) |field| {
                                    if (std.mem.eql(u8, method, field.name)) {
                                        break :method @intToEnum(http.Method, field.value);
                                    }
                                }
                                return error.InvalidHttpMethod;
                            };
                            log.debug("Method: {any}", .{self.method});

                            if (path.len > self.path_buf.len) {
                                return error.PathTooLong;
                            }
                            self.path = self.path_buf[0..path.len];
                            std.mem.copy(u8, self.path.?, path);

                            self.state = .ReadHeaders;
                            return true;
                        } else {
                            return error.InvalidHttpCommandFormat;
                        }
                    } else {
                        return error.InvalidHttpCommandFormat;
                    }
                },

                .ReadHeaders => {
                    // name: value
                    if (line.len == 0) {
                        // End of headers
                        // TODO: See if we want to handle POST --GM
                        log.debug("End of headers", .{});
                        self.state = .Done;
                        return false;
                    } else if (std.mem.indexOfPos(u8, line, 0, ": ")) |pos0| {
                        const name = line[0..pos0];
                        const value = line[pos0 + 2 ..];
                        try self.handleHeader(name, value);
                        return true;
                    } else {
                        return error.InvalidHttpHeaderFormat;
                    }
                },

                .Done => {
                    // TODO: Consider handling pipelined sends and all that crap --GM
                    return false;
                },
            }
        }

        fn handleHeader(self: *Self, name: []const u8, value: []const u8) !void {
            log.debug("Handling header: \"{s}\" value: \"{s}\"", .{ name, value });
            inline for (@typeInfo(@TypeOf(self.headers)).Struct.fields) |field| {
                if (std.mem.eql(u8, field.name, name)) {
                    const realType = @typeInfo(field.type).Optional.child;
                    switch (@typeInfo(realType)) {
                        .Enum => |ti| {
                            inline for (ti.fields) |ef| {
                                if (std.mem.eql(u8, ef.name, value)) {
                                    @field(self.headers, field.name) = @intToEnum(realType, ef.value);
                                    return;
                                }
                            }
                            // Otherwise, log and warn.
                            log.warn("Unhandled enum \"{s}\" value \"{s}\"", .{ name, value });
                        },
                        else => unreachable,
                    }
                    return;
                }
            }
        }
    };
}
