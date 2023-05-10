// SPDX-License-Identifier: AGPL-3.0-or-later
const std = @import("std");
const log = std.log.scoped(.webserver_types);
const http = std.http;

pub const ConnectionType = enum {
    close,
    // Both capitalisations are a thing and it's stupid and ill-defined. --GM
    @"Keep-Alive",
    @"keep-alive",
};
