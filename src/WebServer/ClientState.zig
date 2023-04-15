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

        state: enum(u8) {
            Read,
            Write,
            Unconnected,
        } = .Unconnected,

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
            self.state = .Read;
            self.accum_buf_used = 0;
            self.request = Request{ .parent = self };
            self.response = null;
        }

        pub fn expectedPollEvents(self: *Self) @TypeOf(@intToPtr(*allowzero os.pollfd, 0).events) {
            return switch (self.state) {
                .Read => os.POLL.IN,
                .Write => os.POLL.OUT,
                else => 0,
            };
        }

        pub fn update(self: *Self) !void {
            switch (self.state) {
                .Read => {
                    while (try self.updateRecv(self.accum_buf[self.accum_buf_used..])) |ncount| {
                        //const indata = self.accum_buf[self.accum_buf_used..][0..ncount];
                        //log.debug("Recv: {d} <<{s}>>", .{ indata.len, indata });
                        self.accum_buf_used += ncount;
                        try self.updateRecvSplitLines();
                    }
                    if (self.request.?.state == .Done) {
                        // Cut the accum buf short
                        self.accum_buf_sent = 0;
                        self.accum_buf_used = 0;
                        // Write our response
                        self.state = .Write;
                    }
                },

                .Write => {
                    while (true) {
                        if (self.accum_buf_sent < self.accum_buf_used) {
                            const sentlen = os.send(
                                self.sockfd,
                                self.accum_buf[self.accum_buf_sent..self.accum_buf_used],
                                os.MSG.DONTWAIT,
                            ) catch |err| switch (err) {
                                error.WouldBlock => return, // Skip if we're unable to send.
                                else => return err,
                            };
                            //const sent = self.accum_buf[self.accum_buf_sent..][0..sentlen];
                            //log.debug("Send: {d} <<{s}>>", .{ sentlen, sent });
                            self.accum_buf_sent += sentlen;
                        } else if (self.response.?.state == .WriteFlushClose) {
                            switch (self.response.?.headers.Connection.?) {
                                .close => {
                                    self.deinit();
                                },
                                .@"keep-alive", .@"Keep-Alive" => {
                                    self.initNextRequest();
                                },
                            }
                            return;
                        } else {
                            self.accum_buf_sent = 0;
                            self.accum_buf_used = 0;
                            self.accum_buf_used += switch (self.response.?.state) {
                                .WriteCommand => try self.updateWriteCommand(self.accum_buf[self.accum_buf_used..]),
                                .WriteHeaders => try self.updateWriteHeaders(self.accum_buf[self.accum_buf_used..]),
                                .WriteBody => self.updateWriteBody() catch |err| switch (err) {
                                    error.WouldBlock => return, // Skip if we're unable to send.
                                    else => return err,
                                },
                                else => unreachable,
                            };
                        }
                    }
                },
                else => {},
            }
        }

        fn updateWriteCommand(self: *Self, buf: []u8) !usize {
            const response = &(self.response.?);
            const status = response.status;
            const result = (try std.fmt.bufPrint(
                buf,
                "HTTP/1.1 {d} {s}\r\n",
                .{ @enumToInt(status), status.phrase() orelse "???" },
            )).len;
            response.state = .WriteHeaders;
            return result;
        }

        fn updateWriteHeaders(self: *Self, buf: []u8) !usize {
            const response = &(self.response.?);
            const headers = &(response.headers);
            inline for (@typeInfo(@TypeOf(headers.*)).Struct.fields, 0..) |field, i| {
                if (i >= response.header_idx) {
                    if (@field(headers.*, field.name)) |value| {
                        response.header_idx = i + 1;
                        return (try std.fmt.bufPrint(
                            buf,
                            switch (field.type) {
                                []const u8, []u8, ?[]const u8, ?[]u8 => "{s}: {s}\r\n",
                                else => switch (@typeInfo(field.type)) {
                                    .Enum => "{s}: {s}\r\n",
                                    else => "{s}: {any}\r\n",
                                },
                            },
                            .{
                                field.name, switch (@typeInfo(field.type)) {
                                    .Enum => |eti| switch (value) {
                                        inline eti.fields => |efield| efield.name,
                                    },
                                    else => value,
                                },
                            },
                        )).len;
                    }
                }
            }
            // No more headers, now write the header terminator and move onto the body
            response.state = .WriteBody;
            return (try std.fmt.bufPrint(buf, "\r\n", .{})).len;
        }

        fn updateWriteBody(self: *Self) !usize {
            const response = &(self.response.?);
            if (response.body_buf) |body_buf| {
                const remain = body_buf[response.body_written..];
                const sentlen = try os.send(
                    self.sockfd,
                    remain,
                    os.MSG.DONTWAIT,
                ); // error.WouldBlock will be caught from above
                //log.debug("Sent {d}/{d}", .{ sentlen, remain.len });
                response.body_written += sentlen;
                if (response.body_written == body_buf.len) {
                    response.state = .WriteFlushClose;
                }
            } else {
                // We're done with this respons with this response. Do the next one!
                response.state = .WriteFlushClose;
            }
            // Don't fill the accum buffer, we're sending directly
            return 0;
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

        pub fn prepareResponse(self: *Self) !void {
            var response = try self.parent.?.handleRequest(self, &self.request.?);
            response.headers.@"Content-Length" = if (response.body_buf) |body_buf|
                body_buf.len
            else
                0;
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
