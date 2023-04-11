const std = @import("std");
const os = std.os;
const log = std.log.scoped(.webserver);
const Allocator = std.mem.Allocator;
const http = std.http;

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

const Self = @This();
// TODO: Allow a custom port --GM
pub const PORT = 10536;
allocator: Allocator,
server: http.Server,
response: ?*http.Server.Response = null,

pub fn new(allocator: Allocator) !Self {
    var server = http.Server.init(allocator, .{
        .reuse_address = true,
    });
    errdefer server.deinit();
    // FIXME: this MUST dual-stack IPv6 + IPv4! --GM
    try server.listen(try std.net.Address.parseIp6("::", PORT));

    return Self{
        .allocator = allocator,
        .server = server,
    };
}

pub fn free(self: *Self) void {
    if (self.response) |response| {
        response.reset();
        self.allocator.destroy(response);
        self.response = null;
    }
    self.server.deinit();
}

pub fn update(self: *Self) !void {
    // If we don't have a Response object, check for a connection
    // FIXME: Handle more than one request at a time --GM
    if (self.response == null) {
        // Listen if possible
        if (self.server.socket.sockfd) |sockfd| {
            // poll to reduce blocking
            // timeout in msecs, negative = infinite, 0 = immediate
            var polls = [_]os.pollfd{
                .{ .fd = sockfd, .events = os.POLL.IN, .revents = 0 },
            };
            const poll_result = try os.poll(&polls, 0);
            if (poll_result < 0) return error.PollFailed;
            if ((polls[0].revents & os.POLL.IN) != 0) {
                // Ready to listen, let's go!
                self.response = try self.server.accept(.{ .dynamic = 16 * 1024 });
            }
        }
    }

    // If we have a Response, advance it
    if (self.response) |response| {
        defer {
            self.allocator.destroy(response);
            self.response = null;
        }
        self.attemptResponse(response) catch |err| switch (err) {
            error.BrokenPipe => {
                log.info("Got broken pipe from HTTP client", .{});
            },
            else => {
                return err;
            },
        };
    }
}

fn attemptResponse(self: *Self, response: *http.Server.Response) !void {
    _ = self;
    // FIXME: The API for this is blocking in 0.11.0-dev.2477+2ee328995.
    // We will have to handle this part ourselves. --GM
    try response.wait();
    const http_path = response.request.headers.target;
    // FIXME: Check headers properly incl. methods --GM
    // TODO: Consider splitting the ? and any trailing / off the path --GM
    const result = blobBody: {
        for (file_list) |entry| {
            if (std.mem.eql(u8, http_path, entry.name)) {
                break :blobBody &entry;
            }
        }
        break :blobBody &err404;
    };
    response.headers.status = result.status;
    response.headers.connection = .close;
    response.headers.transfer_encoding = .{ .content_length = result.blob.len };
    // vvv WARNING DO NOT LET THIS LEAVE SCOPE UNTIL IT'S SENT
    var custom_headers = [_]http.CustomHeader{
        .{ .name = "Content-Type", .value = result.mime },
    };
    response.headers.custom = &custom_headers;
    try response.do();
    // ^^^ SCOPE IS NOW FINE I HOPE
    const count = try response.write(result.blob);
    if (count != result.blob.len) {
        return error.Dammit;
    }
    try response.finish();
}
