const std = @import("std");
const log = std.log.scoped(.webserver_client);
const os = std.os;
const http = std.http;

const static_pool = @import("../static_pool.zig");
const StaticPoolChainedItem = static_pool.StaticPoolChainedItem;

const http_types = @import("http_types.zig");

pub fn ClientState(comptime Parent: type) type {
    return struct {
        const Self = @This();
        pub const Request = @import("Request.zig").Request(Self);
        pub const Response = @import("Response.zig").Response(Self);
        pub const ChainedRequest = StaticPoolChainedItem(Request);
        pub const ChainedResponse = StaticPoolChainedItem(Response);
        pub const InitOptions = struct {
            parent: *Parent,
            sockfd: os.fd_t,
            addr: *const os.sockaddr.in6,
        };
        parent: ?*Parent = null,
        sockfd: os.fd_t = 0,
        addr: os.sockaddr.in6 = undefined,
        request: ?*ChainedRequest = null,
        response: ?*ChainedResponse = null,

        /// Initialises the client state.
        pub fn init(self: *Self, options: InitOptions) !void {
            self.parent = options.parent;
            self.sockfd = options.sockfd;
            self.addr = options.addr.*;
            try self.initNextRequest();
        }

        /// Deinitialises and disowns the client state.
        pub fn deinit(self: *Self) void {
            log.debug("Deinitialising client", .{});
            if (self.sockfd != 0) {
                os.closeSocket(self.sockfd);
                self.sockfd = 0;
            }
            self.request = null;
            self.response = null;
            log.debug("Client closed", .{});
        }

        fn initNextRequest(self: *Self) !void {
            log.debug("Prepping next request", .{});
            self.request = try self.parent.?.requests.tryAcquire(.{ .parent = self });
            if (self.request == null) {
                return error.CannotAllocateRequest;
            }
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

        pub fn update(self: *Self, wants_recv: bool) !void {
            if (wants_recv) {
                if (self.request) |request| {
                    // TODO: Handle request parsing while response is active --GM
                    if (self.response != null) @panic("conflict with accum_buf with request and response both active!");
                    requestLoop: while (try request.child.update()) {
                        if (request.child.isDone()) break :requestLoop;
                    }
                    if (request.child.isDone()) {
                        try self.prepareResponse();
                    }
                }
            }

            if (self.response) |response| {
                responseLoop: while (true) {
                    if (response.child.accum_buf_sent < response.child.accum_buf_used) {
                        const sentlen = self.write(
                            response.child.accum_buf[response.child.accum_buf_sent..response.child.accum_buf_used],
                        ) catch |err| switch (err) {
                            error.WouldBlock => break :responseLoop, // Skip if we're unable to send.
                            else => return err,
                        };
                        response.child.accum_buf_sent += sentlen;
                    } else if (response.child.isDone()) {
                        switch (response.child.headers.Connection.?) {
                            .close => {
                                self.deinit();
                            },
                            .@"keep-alive", .@"Keep-Alive" => {
                                try self.initNextRequest();
                            },
                        }
                        self.response = null;
                        break :responseLoop;
                    } else {
                        response.child.accum_buf_sent = 0;
                        response.child.accum_buf_used = 0;
                        response.child.accum_buf_used += response.child.updateWrite(
                            response.child.accum_buf[response.child.accum_buf_used..],
                        ) catch |err| switch (err) {
                            error.WouldBlock => break :responseLoop, // Skip if we're unable to send.
                            else => return err,
                        };
                    }
                }
            }
        }

        pub fn read(self: *Self, buf: []u8) !usize {
            const recvlen = os.recv(
                self.sockfd,
                buf,
                os.MSG.DONTWAIT,
            );
            return recvlen;
        }

        pub fn write(self: *Self, buf: []const u8) !usize {
            const sentlen = try os.send(
                self.sockfd,
                buf,
                os.MSG.DONTWAIT,
            );
            return sentlen;
        }

        fn prepareResponse(self: *Self) !void {
            var response = try self.parent.?.handleRequest(self, &self.request.?.child);
            response.child.headers.@"Content-Length" = if (response.child.body_buf) |body_buf|
                body_buf.len
            else
                0;
            self.request = null;
            self.response = response;
        }
    };
}
