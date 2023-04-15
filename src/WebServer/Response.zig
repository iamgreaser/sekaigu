const std = @import("std");
const log = std.log.scoped(.webserver_request);
const http = std.http;

pub const RESPONSE_ACCUM_BUF_SIZE = 192;

const http_types = @import("http_types.zig");
const ConnectionType = http_types.ConnectionType;

pub fn Response(comptime Parent: type) type {
    return struct {
        const Self = @This();
        pub const Headers = struct {
            @"Content-Type": ?[]const u8 = null,
            @"Content-Length": ?usize = null,
            Location: ?[]const u8 = null,
            Connection: ?ConnectionType = .close,
        };
        pub const InitOptions = struct {
            parent: *Parent,
            status: http.Status,
            body_buf: ?[]const u8,
            headers: Headers,
        };

        parent: *Parent,
        status: http.Status,
        body_buf: ?[]const u8,
        headers: Headers,

        accum_buf: [RESPONSE_ACCUM_BUF_SIZE]u8 = undefined,
        accum_buf_used: usize = 0,
        accum_buf_sent: usize = 0,

        header_idx: usize = 0,
        body_written: usize = 0,

        state: enum(u8) {
            WriteCommand,
            WriteHeaders,
            WriteBody,
            Done,
        } = .WriteCommand,

        pub fn init(self: *Self, options: InitOptions) !void {
            self.* = Self{
                .parent = options.parent,
                .status = options.status,
                .body_buf = options.body_buf,
                .headers = options.headers,
            };
        }

        pub fn deinit(self: *Self) void {
            _ = self;
        }

        pub fn isDone(self: *const Self) bool {
            return self.state == .Done;
        }

        pub fn updateWrite(self: *Self, buf: []u8) !usize {
            return switch (self.state) {
                .WriteCommand => self.updateWriteCommand(buf),
                .WriteHeaders => self.updateWriteHeaders(buf),
                .WriteBody => self.updateWriteBody(),
                .Done => 0,
            };
        }

        fn updateWriteCommand(self: *Self, buf: []u8) !usize {
            const status = self.status;
            const result = (try std.fmt.bufPrint(
                buf,
                "HTTP/1.1 {d} {s}\r\n",
                .{ @enumToInt(status), status.phrase() orelse "???" },
            )).len;
            self.state = .WriteHeaders;
            return result;
        }

        fn updateWriteHeaders(self: *Self, buf: []u8) !usize {
            const headers = &(self.headers);
            inline for (@typeInfo(@TypeOf(headers.*)).Struct.fields, 0..) |field, i| {
                if (i >= self.header_idx) {
                    if (@field(headers.*, field.name)) |value| {
                        self.header_idx = i + 1;
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
            self.state = .WriteBody;
            return (try std.fmt.bufPrint(buf, "\r\n", .{})).len;
        }

        fn updateWriteBody(self: *Self) !usize {
            if (self.body_buf) |body_buf| {
                const remain = body_buf[self.body_written..];
                const sentlen = try self.parent.write(remain); // error.WouldBlock will be caught from above
                //log.debug("Sent {d}/{d}", .{ sentlen, remain.len });
                self.body_written += sentlen;
                if (self.body_written == body_buf.len) {
                    self.state = .Done;
                }
            } else {
                // We're done with this response. Do the next one!
                self.state = .Done;
            }
            // Don't fill the accum buffer, we're sending directly
            return 0;
        }
    };
}
