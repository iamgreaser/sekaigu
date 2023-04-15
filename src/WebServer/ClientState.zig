const std = @import("std");
const log = std.log.scoped(.webserver_client);
const os = std.os;
const http = std.http;

pub const CLIENT_BUF_SIZE = 192;

const http_types = @import("http_types.zig");

pub fn ClientState(comptime Parent: type) type {
    return struct {
        const Self = @This();
        pub const Request = @import("Request.zig").Request(Self);
        pub const Response = @import("Response.zig").Response(Self);
        parent: ?*Parent = null,
        prev: ?*Self = null,
        next: ?*Self = null,
        sockfd: os.fd_t = 0,
        addr: os.sockaddr.in6 = undefined,
        accum_buf: [CLIENT_BUF_SIZE]u8 = undefined,
        accum_buf_used: usize = 0,
        accum_buf_sent: usize = 0,
        request: ?Request = null,
        response: ?Response = null,

        /// Initialises the client state, except for the previous and next indices.
        pub fn init(self: *Self, sockfd: os.fd_t, addr: *os.sockaddr.in6) void {
            self.sockfd = sockfd;
            self.addr = addr.*;
            self.initNextRequest();
            self.moveRing(&self.parent.?.first_free_client, &self.parent.?.first_used_client);
        }

        /// Deinitialises and disowns the client state.
        pub fn deinit(self: *Self) void {
            log.debug("Deinitialising client", .{});
            if (self.sockfd != 0) {
                os.closeSocket(self.sockfd);
                self.sockfd = 0;
                self.moveRing(&self.parent.?.first_used_client, &self.parent.?.first_free_client);
            }
            self.request = null;
            self.response = null;
            log.debug("Client closed", .{});
        }

        fn initNextRequest(self: *Self) void {
            log.debug("Prepping next request", .{});
            self.accum_buf_used = 0;
            self.request = Request{ .parent = self };
            self.response = null;
        }

        const ipollevents = @TypeOf(@intToPtr(*allowzero os.pollfd, 0).events);
        pub fn expectedPollEvents(self: *Self) ipollevents {
            var result: ipollevents = 0;
            if (self.request != null) {
                result |= os.POLL.IN;
            }
            if (self.response != null) {
                result |= os.POLL.OUT;
            }
            return result;
        }

        pub fn update(self: *Self) !void {
            if (self.request) |*request| {
                // TODO: Handle request parsing while response is active --GM
                if (self.response != null) @panic("conflict with accum_buf with request and response both active!");
                requestLoop: while (try self.updateRecv(self.accum_buf[self.accum_buf_used..])) |ncount| {
                    //const indata = self.accum_buf[self.accum_buf_used..][0..ncount];
                    //log.debug("Recv: {d} <<{s}>>", .{ indata.len, indata });
                    self.accum_buf_used += ncount;
                    try self.updateRecvSplitLines();
                    if (request.isDone()) break :requestLoop;
                }
                if (request.isDone()) {
                    try self.prepareResponse();
                }
            }

            if (self.response) |*response| {
                responseLoop: while (true) {
                    if (self.accum_buf_sent < self.accum_buf_used) {
                        const sentlen = self.write(
                            self.accum_buf[self.accum_buf_sent..self.accum_buf_used],
                        ) catch |err| switch (err) {
                            error.WouldBlock => break :responseLoop, // Skip if we're unable to send.
                            else => return err,
                        };
                        self.accum_buf_sent += sentlen;
                    } else if (response.isDone()) {
                        switch (response.headers.Connection.?) {
                            .close => {
                                self.deinit();
                            },
                            .@"keep-alive", .@"Keep-Alive" => {
                                self.initNextRequest();
                            },
                        }
                        self.response = null;
                        break :responseLoop;
                    } else {
                        self.accum_buf_sent = 0;
                        self.accum_buf_used = 0;
                        self.accum_buf_used += response.updateWrite(
                            self.accum_buf[self.accum_buf_used..],
                        ) catch |err| switch (err) {
                            error.WouldBlock => break :responseLoop, // Skip if we're unable to send.
                            else => return err,
                        };
                    }
                }
            }
        }

        pub fn write(self: *Self, buf: []const u8) !usize {
            const sentlen = try os.send(
                self.sockfd,
                buf,
                os.MSG.DONTWAIT,
            );
            return sentlen;
        }

        fn updateRecv(self: *Self, buf: []u8) !?usize {
            if (buf.len == 0) {
                return error.LineTooLong;
            }
            const recvlen = os.recv(self.sockfd, buf, os.MSG.DONTWAIT) catch |err| switch (err) {
                error.WouldBlock => return null, // Skip if we've run out of stuff to consume.
                else => return err,
            };
            if (recvlen == 0) {
                return error.EndOfStream;
            }
            return recvlen;
        }

        fn updateRecvSplitLines(self: *Self) !void {
            const CRLF = "\r\n";
            var begoffs: usize = 0;
            splitting: while (std.mem.indexOfPos(u8, self.accum_buf[0..self.accum_buf_used], begoffs, CRLF)) |pos| {
                const keep_splitting = try self.request.?.parseLine(self.accum_buf[begoffs..pos]);
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

        fn prepareResponse(self: *Self) !void {
            var response = try self.parent.?.handleRequest(self, &self.request.?);
            response.headers.@"Content-Length" = if (response.body_buf) |body_buf|
                body_buf.len
            else
                0;
            self.request = null;
            self.response = response;
        }

        /// Moves this client from one ring to another.
        fn moveRing(self: *Self, from_root: *?*Self, to_root: *?*Self) void {
            // Detach from current ring
            if (self.next) |next| {
                next.prev = self.prev;
            }
            if (self.prev) |prev| {
                prev.next = self.next;
            } else {
                from_root.* = self.next;
            }

            // Prepend to new ring
            self.prev = null;
            self.next = to_root.*;
            if (to_root.*) |first| {
                first.prev = self;
            }
            to_root.* = self;
        }
    };
}
