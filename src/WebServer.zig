const builtin = @import("builtin");
const std = @import("std");
const os = std.os;
const log = std.log.scoped(.webserver);
const Allocator = std.mem.Allocator;
const http = std.http;

// TODO: Allow a custom port --GM
pub const PORT = 10536;
pub const MAX_CLIENTS = 128;
pub const CLIENT_BUF_SIZE = 128;
pub const PATH_BUF_SIZE = 64;
pub const CONN_BACKLOG = 10;

// std.http.Server simply does not cut it for our purposes:
// - It's strictly blocking, unless you use async, which has been temporarily removed
// - You could use a thread... for every request
// - We need websockets
// It worked well enough for testing, but now it's time to replace it...
// So here's our own web server. Enjoy!
//
// ...also, Zig's networking doesn't cut it either, as we
// So we use our own!
//
// TODO: Windows support - that is, we're likely to need select() instead of poll()... but not sure why select() isn't defined in os.linux? --GM
//
const HttpConnectionType = enum {
    close,
    // Both capitalisations are a thing and it's stupid and ill-defined. --GM
    @"Keep-Alive",
    @"keep-alive",
};

const HttpRequest = struct {
    const Self = @This();
    method: ?http.Method = null,
    headers: struct {
        Connection: ?HttpConnectionType = .close,
    } = .{},
    path_buf: [PATH_BUF_SIZE]u8 = undefined,
    path: ?[]u8 = null,
};
const HttpResponse = struct {
    const Self = @This();
    status: http.Status,
    body_buf: []const u8,
    headers: struct {
        @"Content-Type": ?[]const u8 = null,
        @"Content-Length": ?usize = null,
        Connection: ?HttpConnectionType = .close,
    } = .{},
    header_idx: usize = 0,
    body_written: usize = 0,
};

const ClientState = struct {
    const Self = @This();
    parent: ?*WebServer = null,
    prev: ?*Self = null,
    next: ?*Self = null,
    sockfd: os.fd_t = 0,
    addr: os.sockaddr.in6 = undefined,
    accum_buf: [CLIENT_BUF_SIZE]u8 = undefined,
    accum_buf_used: usize = 0,
    accum_buf_sent: usize = 0,
    request: ?HttpRequest = null,
    response: ?HttpResponse = null,

    state: enum(u8) {
        Unconnected,
        ReadCommand,
        ReadHeaders,
        //ReadBody, // Supporting this would make this use more dynamic RAM allocation --GM
        WriteCommand,
        WriteHeaders,
        WriteBody,
        WriteFlushClose,
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
        self.state = .ReadCommand;
        self.accum_buf_used = 0;
        self.request = HttpRequest{};
        self.response = null;
    }

    pub fn update(self: *Self) !void {
        switch (self.state) {
            .ReadCommand, .ReadHeaders => {
                while (try self.updateRecv(self.accum_buf[self.accum_buf_used..])) |ncount| {
                    //const indata = self.accum_buf[self.accum_buf_used..][0..ncount];
                    //log.debug("Recv: {d} <<{s}>>", .{ indata.len, indata });
                    self.accum_buf_used += ncount;
                    try self.updateRecvSplitLines();
                }
            },

            .WriteCommand, .WriteHeaders, .WriteBody, .WriteFlushClose => {
                while (true) {
                    if (self.accum_buf_sent < self.accum_buf_used) {
                        const sentlen = os.send(
                            self.sockfd,
                            self.accum_buf[self.accum_buf_sent..self.accum_buf_used],
                            os.MSG.DONTWAIT,
                        ) catch |err| switch (err) {
                            error.WouldBlock => return, // Skip if we've run out of stuff to send.
                            else => return err,
                        };
                        //const sent = self.accum_buf[self.accum_buf_sent..][0..sentlen];
                        //log.debug("Send: {d} <<{s}>>", .{ sentlen, sent });
                        self.accum_buf_sent += sentlen;
                    } else if (self.state == .WriteFlushClose) {
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
                        self.accum_buf_used += switch (self.state) {
                            .WriteCommand => try self.updateWriteCommand(self.accum_buf[self.accum_buf_used..]),
                            .WriteHeaders => try self.updateWriteHeaders(self.accum_buf[self.accum_buf_used..]),
                            .WriteBody => try self.updateWriteBody(self.accum_buf[self.accum_buf_used..]),
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
        const result = (try std.fmt.bufPrint(
            buf,
            "HTTP/1.1 {d} {s}\r\n",
            .{ response.status, response.status.phrase() orelse "???" },
        )).len;
        self.state = .WriteHeaders;
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
                            else => "{s}: {any}\r\n",
                        },
                        .{ field.name, value },
                    )).len;
                }
            }
        }
        // No more headers, now write the header terminator and move onto the body
        self.state = .WriteBody;
        return (try std.fmt.bufPrint(buf, "\r\n", .{})).len;
    }

    fn updateWriteBody(self: *Self, buf: []u8) !usize {
        const response = &(self.response.?);
        const remain = response.body_buf[response.body_written..];
        const remain_len = @min(remain.len, buf.len);
        std.mem.copy(u8, buf, remain[0..remain_len]);
        response.body_written += remain_len;
        if (response.body_written == response.body_buf.len) {
            self.state = .WriteFlushClose;
        }
        return remain_len;
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

    fn parseLine(self: *Self, line: []const u8) !bool {
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
                        self.request.?.method = method: {
                            inline for (@typeInfo(http.Method).Enum.fields) |field| {
                                if (std.mem.eql(u8, method, field.name)) {
                                    break :method @intToEnum(http.Method, field.value);
                                }
                            }
                            return error.InvalidHttpMethod;
                        };
                        log.debug("Method: {any}", .{self.request.?.method});

                        if (path.len > self.request.?.path_buf.len) {
                            return error.PathTooLong;
                        }
                        self.request.?.path = self.request.?.path_buf[0..path.len];
                        std.mem.copy(u8, self.request.?.path.?, path);

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
                    try self.prepareResponse();
                    self.state = .WriteCommand;
                    // Cut the accum buf short
                    self.accum_buf_sent = 0;
                    self.accum_buf_used = 0;
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
            else => unreachable,
        }
    }

    fn handleHeader(self: *Self, name: []const u8, value: []const u8) !void {
        log.debug("Handling header: \"{s}\" value: \"{s}\"", .{ name, value });
        const request = &self.request.?;
        inline for (@typeInfo(@TypeOf(request.headers)).Struct.fields) |field| {
            if (std.mem.eql(u8, field.name, name)) {
                const realType = @typeInfo(field.type).Optional.child;
                switch (@typeInfo(realType)) {
                    .Enum => |ti| {
                        inline for (ti.fields) |ef| {
                            if (std.mem.eql(u8, ef.name, value)) {
                                @field(request.headers, field.name) = @intToEnum(realType, ef.value);
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

    fn prepareResponse(self: *Self) !void {
        self.response = try self.parent.?.handleRequest(self, &self.request.?);
        self.response.?.headers.@"Content-Length" = self.response.?.body_buf.len;
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

pub const WebServer = struct {
    const Self = @This();
    allocator: Allocator = undefined,
    server_sockfd: os.socket_t = -1,
    clients: [MAX_CLIENTS]ClientState = [1]ClientState{ClientState{}} ** MAX_CLIENTS,
    first_free_client: ?*ClientState = null,
    first_used_client: ?*ClientState = null,

    //server: http.Server,
    //response: ?*http.Server.Response = null,

    // Embedded files
    const FileNameAndBlob = struct {
        name: []const u8,
        mime: []const u8,
        blob: []const u8,
        status: http.Status = .ok,
    };
    const file_list = [_]FileNameAndBlob{
        .{ .name = "/", .mime = "text/html", .blob = @embedFile("glue-page.html") },

        // Ah yes, JavaScript continues to be a pile of JavaScript.
        // - text/javascript is the original de-facto standard, and you can thank Microsoft for this.
        // - application/javascript is the official standard as per RFC4329 from 2006.
        // - application/x-javascript was apparently somewhat popular for some time.
        // If application/javascript fails, let me know. --GM
        .{ .name = "/glue-page.js", .mime = "application/javascript", .blob = @embedFile("glue-page.js") },

        .{ .name = "/sekaigu.wasm", .mime = "application/wasm", .blob = @embedFile("sekaigu_wasm_bin") },
    };

    const err404 = FileNameAndBlob{
        .name = "/err/404",
        .mime = "text/plain",
        .blob = "404 Not Found",
        .status = .not_found,
    };

    pub fn init(self: *Self, allocator: Allocator) !void {
        log.info("Initialising web server", .{});
        var server_sockfd = try os.socket(os.AF.INET6, os.SOCK.STREAM | os.SOCK.NONBLOCK, os.IPPROTO.TCP);
        errdefer os.closeSocket(server_sockfd);
        const sock_addr = os.sockaddr.in6{
            .port = std.mem.nativeToBig(u16, PORT),
            .addr = [1]u8{0} ** 16,
            .flowinfo = 0,
            .scope_id = 0,
        };

        try os.setsockopt(
            server_sockfd,
            os.SOL.SOCKET,
            os.SO.REUSEPORT,
            @ptrCast([*]const u8, &@as(i32, 1))[0..@sizeOf(i32)],
        );
        // FIXME: Zig does not expose IPV6_V6ONLY properly when libc is used, so we have to use the constants. --GM
        //try os.setsockopt(server_sockfd, os.IPPROTO.IPV6, os.system.IPV6.V6ONLY, "\x00");
        try os.setsockopt(
            server_sockfd,
            os.IPPROTO.IPV6,
            if (builtin.os.tag == .linux) 26 else 27,
            @ptrCast([*]const u8, &@as(i32, 0))[0..@sizeOf(i32)],
        );
        try os.bind(server_sockfd, @ptrCast(*const os.sockaddr, &sock_addr), @sizeOf(@TypeOf(sock_addr)));
        try os.listen(server_sockfd, CONN_BACKLOG);

        self.* = Self{
            .allocator = allocator,
            .server_sockfd = server_sockfd,
        };
        // Create free chain
        self.first_free_client = &self.clients[0];
        for (&self.clients, 0..) |*client, i| {
            client.parent = self;
            client.prev = if (i == 0) null else &self.clients[i - 1];
            client.next = if (i == MAX_CLIENTS - 1) null else &self.clients[i + 1];
        }
        log.info("Web server initialised", .{});
    }

    pub fn deinit(self: *Self) void {
        log.info("Shutting down web server", .{});
        while (self.first_used_client) |client| {
            client.deinit();
        }
        if (self.server_sockfd >= 0) {
            os.closeSocket(self.server_sockfd);
            self.server_sockfd = -1;
        }
        log.info("Web server deinitialised", .{});
    }

    pub fn update(self: *Self) !void {
        // Poll for new clients
        var server_poll = [_]os.pollfd{.{
            .fd = self.server_sockfd,
            .events = os.POLL.IN,
            .revents = 0,
        }};
        _ = try os.poll(&server_poll, 0);
        if ((server_poll[0].revents & os.POLL.IN) != 0) {
            log.info("Connecting a new client", .{});
            var sock_addr: os.sockaddr.in6 = undefined;
            var sock_addr_len: u32 = @sizeOf(@TypeOf(sock_addr));
            const client_sockfd = try os.accept(
                self.server_sockfd,
                @ptrCast(*os.sockaddr, &sock_addr),
                &sock_addr_len,
                0,
            );
            errdefer os.close(client_sockfd);
            if (sock_addr.family != os.AF.INET6) {
                return error.UnexpectedSocketFamilyOnAccept;
            }
            if (self.first_free_client) |client| {
                client.init(client_sockfd, &sock_addr);
            } else {
                return error.TooManyClients;
            }
            log.info("Client connected", .{});
        }

        // Update clients
        {
            var client_chain: ?*ClientState = self.first_used_client;
            while (client_chain) |client| {
                client_chain = client.next;
                // On failure, Let It Crash(tm)
                client.update() catch |err| {
                    log.err("HTTP client error, terminating: {}", .{err});
                    client.deinit();
                };
            }
        }
    }

    pub fn handleRequest(self: *Self, client: *ClientState, request: *HttpRequest) !HttpResponse {
        _ = self;
        _ = client;

        const info: *const FileNameAndBlob = info: {
            const path = request.path.?;
            for (&file_list) |*info| {
                if (std.mem.eql(u8, info.name, path)) {
                    break :info info;
                }
            }
            break :info &err404;
        };

        return HttpResponse{
            .status = info.status,
            .headers = .{
                .@"Content-Type" = info.mime,
                .Connection = request.headers.Connection.?,
            },
            .body_buf = info.blob,
        };
    }
};
