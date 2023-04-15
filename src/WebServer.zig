const builtin = @import("builtin");
const std = @import("std");
const log = std.log.scoped(.webserver);
const os = std.os;
const http = std.http;

// TODO: Allow a custom port --GM
pub const PORT = 10536;
pub const POLL_TIMEOUT_MSEC = 200; // How often do we ensure that we wake this thread?
pub const MAX_CLIENTS = 128;
pub const MAX_HTTP_REQUESTS = 32;
pub const MAX_HTTP_RESPONSES = 128;
pub const CONN_BACKLOG = 10;

const static_pool = @import("static_pool.zig");
const StaticPool = static_pool.StaticPool;

// std.http.Server simply does not cut it for our purposes:
// - It's strictly blocking, unless you use async, which has been temporarily removed
// - You could use a thread... for every request
// - We need websockets
// It worked well enough for testing, but now it's time to replace it...
// So here's our own web server. Enjoy!
//
// ...also, Zig's networking doesn't cut it either, as we need UDP for the non-HTTP/WebSocket stuff.
// So we use our own!
//
// TODO: Windows support - that is, we're likely to need select() instead of poll()... but not sure why select() isn't defined in os.linux? --GM
//
const http_types = @import("WebServer/http_types.zig");
const ClientState = @import("WebServer/ClientState.zig").ClientState(WebServer);
const Request = ClientState.Request;
const Response = ClientState.Response;
const ChainedRequest = ClientState.ChainedRequest;
const ChainedResponse = ClientState.ChainedResponse;

pub const WebServer = struct {
    const Self = @This();
    const ClientPool = StaticPool(ClientState);
    const RequestPool = StaticPool(Request);
    const ResponsePool = StaticPool(Response);
    const ChainedClientState = ClientPool.ChainedItem;

    clients_backing: [MAX_CLIENTS]ClientPool.ChainedItem = [1]ClientPool.ChainedItem{ClientPool.ChainedItem{}} ** MAX_CLIENTS,
    clients: ClientPool = ClientPool{},
    requests_backing: [MAX_HTTP_REQUESTS]RequestPool.ChainedItem = [1]RequestPool.ChainedItem{RequestPool.ChainedItem{}} ** MAX_HTTP_REQUESTS,
    requests: RequestPool = RequestPool{},
    responses_backing: [MAX_HTTP_RESPONSES]ResponsePool.ChainedItem = [1]ResponsePool.ChainedItem{ResponsePool.ChainedItem{}} ** MAX_HTTP_RESPONSES,
    responses: ResponsePool = ResponsePool{},

    server_sockfd: os.socket_t = -1,
    thread: ?std.Thread = null,
    thread_shutdown: std.Thread.ResetEvent = .{},
    poll_list: [1 + MAX_CLIENTS]os.pollfd = undefined,
    poll_clients: [1 + MAX_CLIENTS]?*ChainedClientState = undefined,

    // Embedded files
    const FileNameAndBlob = struct {
        name: []const u8,
        mime: ?[]const u8,
        blob: ?[]const u8,
        status: http.Status = .ok,
        location: ?[]const u8 = null,
    };
    const file_list = [_]FileNameAndBlob{
        .{ .name = "/", .mime = null, .blob = null, .status = .see_other, .location = "/client/" },
        .{ .name = "/client/", .mime = "text/html", .blob = @embedFile("glue-page.html") },

        // Ah yes, JavaScript continues to be a pile of JavaScript.
        // - text/javascript is the original de-facto standard, and you can thank Microsoft for this.
        // - application/javascript is the official standard as per RFC4329 from 2006.
        // - application/x-javascript was apparently somewhat popular for some time.
        // If application/javascript fails, let me know. --GM
        .{ .name = "/client/glue-page.js", .mime = "application/javascript", .blob = @embedFile("glue-page.js") },

        .{ .name = "/client/sekaigu.wasm", .mime = "application/wasm", .blob = @embedFile("sekaigu_wasm_bin") },
    };

    const err404 = FileNameAndBlob{
        .name = "/err/404",
        .mime = "text/plain",
        .blob = "404 Not Found",
        .status = .not_found,
    };

    pub fn init(self: *Self) !void {
        log.info("Initialising web server", .{});
        if (self.thread != null) {
            @panic("Attempted to reinit a WebServer while its thread is running!");
        }
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
            .server_sockfd = server_sockfd,
        };

        // Create chains
        self.clients.init(&self.clients_backing);
        self.requests.init(&self.requests_backing);
        self.responses.init(&self.responses_backing);

        // Create thread
        self.thread_shutdown.reset();
        self.thread = try std.Thread.spawn(
            .{
                .stack_size = 1024 * 64, // Give it 64KB
            },
            Self.updateWorker,
            .{self},
        );
        log.info("Web server initialised", .{});
    }

    pub fn deinit(self: *Self) void {
        log.info("Shutting down web server", .{});
        if (self.thread) |thread| {
            log.info("Stopping thread", .{});
            self.thread_shutdown.set();
            thread.join();
        }

        log.info("Dropping responses", .{});
        self.responses.deinit();
        log.info("Dropping requests", .{});
        self.requests.deinit();

        log.info("Stopping clients", .{});
        self.clients.deinit();

        if (self.server_sockfd >= 0) {
            log.info("Closing socket", .{});
            os.closeSocket(self.server_sockfd);
            self.server_sockfd = -1;
        }
        log.info("Web server deinitialised", .{});
    }

    pub fn update(self: *Self) !void {
        // Do nothing for now - we're running in a thread
        _ = self;
    }

    fn updateWorker(self: *Self) !void {
        while (!self.thread_shutdown.isSet()) {
            try self.updateWorkerTick();
        }
    }

    fn updateWorkerTick(self: *Self) !void {
        // Poll for new clients
        var poll_count: usize = 1;
        self.poll_list[0] = os.pollfd{
            .fd = self.server_sockfd,
            .events = os.POLL.IN,
            .revents = 0,
        };
        self.poll_clients[0] = null;

        {
            var client_iter = self.clients.iterUsed();
            while (client_iter.next()) |client| {
                self.poll_list[poll_count] = os.pollfd{
                    .fd = client.child.sockfd,
                    .events = client.child.expectedPollEvents(),
                    .revents = 0,
                };
                self.poll_clients[poll_count] = client;
                poll_count += 1;
            }
        }

        const polls_to_read = try os.poll(self.poll_list[0..poll_count], POLL_TIMEOUT_MSEC);
        if (polls_to_read == 0) return;
        for (0..poll_count) |i| {
            const p = &self.poll_list[i];
            if (p.fd == self.server_sockfd) {
                // Update server
                if ((p.revents & os.POLL.IN) != 0) {
                    self.acceptNewClient() catch |err| {
                        log.err("Error when attempting to accept a new client: {}", .{err});
                    };
                }
            } else if (self.poll_clients[i]) |client| {
                // Update client
                // On failure, Let It Crash(tm)
                client.child.update((p.revents & os.POLL.IN) != 0) catch |err| {
                    log.err("HTTP client error, terminating: {}", .{err});
                    self.clients.release(client);
                };
            }
        }
    }

    fn acceptNewClient(self: *Self) !void {
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
        if (try self.clients.tryAcquire(.{
            .parent = self,
            .sockfd = client_sockfd,
            .addr = &sock_addr,
        }) == null) {
            return error.TooManyClients;
        } else {
            log.info("Client connected", .{});
        }
    }

    pub fn handleRequest(self: *Self, client: *ClientState, request: *Request) !*ChainedResponse {
        const info: *const FileNameAndBlob = info: {
            const path = request.path.?;
            for (&file_list) |*info| {
                if (std.mem.eql(u8, info.name, path)) {
                    break :info info;
                }
            }
            break :info &err404;
        };

        if (try self.responses.tryAcquire(.{
            .parent = client,
            .status = info.status,
            .headers = .{
                .@"Content-Type" = info.mime,
                .Location = info.location,
                .Connection = switch (request.headers.Connection.?) {
                    //.close => .close,
                    .@"Keep-Alive", .@"keep-alive" => |v| v,
                    // Apparently things which aren't "close" need to be kept alive for HTTP/1.1.
                    // But for older versions, it does need to be "close".
                    else => .close,
                },
            },
            .body_buf = info.blob,
        })) |response| {
            return response;
        } else {
            return error.CannotAllocateResponse;
        }
    }
};
