// SPDX-License-Identifier: AGPL-3.0-or-later
const std = @import("std");
const log = std.log.scoped(.webserver_request);
const http = std.http;

pub const PATH_BUF_SIZE = 64;
pub const REQUEST_ACCUM_BUF_SIZE = 192;

const http_types = @import("http_types.zig");
const ConnectionType = http_types.ConnectionType;

pub fn Request(comptime Parent: type) type {
    return struct {
        const Self = @This();
        pub const Headers = struct {
            Connection: ?ConnectionType = .close,
        };
        pub const InitOptions = struct {
            parent: *Parent,
        };

        parent: *Parent,

        method: ?http.Method = null,
        headers: Headers = .{},
        path_buf: [PATH_BUF_SIZE]u8 = undefined,
        path: ?[]u8 = null,

        accum_buf: [REQUEST_ACCUM_BUF_SIZE]u8 = undefined,
        accum_buf_used: usize = 0,

        state: enum(u8) {
            ReadCommand,
            ReadHeaders,
            //ReadBody, // Supporting this would make this use more dynamic RAM allocation --GM
            Done,
        } = .ReadCommand,

        pub fn init(self: *Self, options: InitOptions) !void {
            self.* = Self{
                .parent = options.parent,
            };
        }

        pub fn deinit(self: *Self) void {
            _ = self;
        }

        pub fn isDone(self: *const Self) bool {
            return self.state == .Done;
        }

        pub fn update(self: *Self) !bool {
            // TODO: Ensure that any extra crap that was sent gets handled as part of a new request --GM
            if (self.state == .Done) return false;
            if (!try self.updateRecvBuf(self.accum_buf[self.accum_buf_used..])) return false;
            try self.updateRecvSplitLines();
            return true;
        }

        fn updateRecvBuf(self: *Self, buf: []u8) !bool {
            if (buf.len == 0) {
                return error.LineTooLong;
            }
            const recvlen = self.parent.read(buf) catch |err| switch (err) {
                error.WouldBlock => return false, // Skip if we've run out of stuff to consume.
                else => return err,
            };
            if (recvlen == 0) {
                return error.EndOfStream;
            }
            self.accum_buf_used += recvlen;
            return true;
        }

        fn updateRecvSplitLines(self: *Self) !void {
            const CRLF = "\r\n";
            var begoffs: usize = 0;
            splitting: while (std.mem.indexOfPos(u8, self.accum_buf[0..self.accum_buf_used], begoffs, CRLF)) |pos| {
                const keep_splitting = try self.parseLine(self.accum_buf[begoffs..pos]);
                begoffs = pos + 2;
                if (!keep_splitting) {
                    break :splitting;
                }
            }
            // Remove consumed lines
            if (self.accum_buf_used != 0) {
                std.mem.copy(
                    u8,
                    self.accum_buf[0..self.accum_buf_used],
                    self.accum_buf[begoffs..self.accum_buf_used],
                );
                self.accum_buf_used -= begoffs;
            }
        }

        pub fn parseLine(self: *Self, line: []const u8) !bool {
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
