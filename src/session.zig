const builtin = @import("builtin");
const std = @import("std");
const log = std.log.scoped(.session);
const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;

const linalg = @import("linalg.zig");
const Vec2f = linalg.Vec2f;
const Vec3f = linalg.Vec3f;
const Vec4f = linalg.Vec4f;
const Mat2f = linalg.Mat2f;
const Mat3f = linalg.Mat3f;
const Mat4f = linalg.Mat4f;

const WebClientState = if (builtin.target.isWasm())
    struct {}
else
    @import("WebServer.zig").ClientState;

pub const PlayerType = union(enum) {
    Local: *LocalPlayer,
    Web: *WebClientState,
};

pub const LocalPlayer = struct {
    //
};

const MAX_PLAYERS = 1000;
pub const Player = struct {
    const Self = @This();
    pub const Id = u16;
    pub const InitOptions = struct {
        player_type: PlayerType,
    };
    pub const SCHEMA = struct {
        id: Id,
        cam_rot: Vec4f,
        cam_pos: Vec4f,
        cam_drot: Vec4f,
        cam_dpos: Vec4f,
    };

    id: Id,
    cam_rot: Vec4f = Vec4f.new(.{ 0.0, 0.0, 0.0, 1.0 }),
    cam_pos: Vec4f = Vec4f.new(.{ 0.0, 0.0, 0.0, 1.0 }),
    cam_drot: Vec4f = Vec4f.new(.{ 0.0, 0.0, 0.0, 0.0 }),
    cam_dpos: Vec4f = Vec4f.new(.{ 0.0, 0.0, 0.0, 0.0 }),

    session: *Session,
    player_type: PlayerType,

    pub fn init(self: *Self, session: *Session, id: Self.Id, options: InitOptions) !void {
        log.info("Creating player", .{});
        self.* = .{
            .session = session,
            .id = id,
            .player_type = options.player_type,
        };
        log.info("Player created", .{});
    }

    pub fn deinit(self: *Self) void {
        log.info("Destroying player", .{});
        _ = self;
        log.info("Player destroyed", .{});
    }
};

/// This contains the full state of the session at any point in time.
/// As a test, this currently only tracks player positions.
pub const Session = struct {
    const Self = @This();
    pub const InitOptions = struct {
        allocator: Allocator,
    };
    pub const SCHEMA = struct {
        // TODO FIXME Find out how to address players in the schema --GM
        players: AutoHashMap(Player.Id, *Player),
    };

    players: AutoHashMap(Player.Id, *Player),
    player_ids_used: [MAX_PLAYERS]bool = [1]bool{false} ** MAX_PLAYERS,

    allocator: Allocator,

    pub fn init(self: *Self, options: InitOptions) !void {
        log.info("Creating session", .{});
        self.* = .{
            .allocator = options.allocator,
            .players = @TypeOf(self.players).init(options.allocator),
        };
        log.info("Session created", .{});
    }

    pub fn deinit(self: *Self) void {
        log.info("Destroying session", .{});
        var iter = self.players.iterator();
        while (iter.next()) |pe| {
            const player: *Player = pe.value_ptr.*;
            player.deinit();
            self.allocator.destroy(player);
        }
        self.players.deinit();
        log.info("Session destroyed", .{});
    }

    fn allocPlayerId(self: *Self) !Player.Id {
        for (&self.player_ids_used, 0..) |*used, i| {
            if (!used.*) {
                var id: Player.Id = @intCast(Player.Id, i);
                used.* = true;
                return id;
            }
        }
        return error.NoMoreIds;
    }

    fn freePlayerId(self: *Self, id: Player.Id) void {
        if (!self.player_ids_used[id]) @panic("Attempted to free an unused player ID!");
        self.player_ids_used[id] = false;
    }

    pub fn addPlayer(self: *Self, options: Player.InitOptions) !*Player {
        var id = try self.allocPlayerId();
        errdefer self.freePlayerId(id);
        var result = try self.allocator.create(Player);
        errdefer self.allocator.destroy(result);
        try result.init(self, id, options);
        errdefer result.deinit();
        try self.players.putNoClobber(id, result);
        return result;
    }

    pub fn removePlayer(self: *Self, player: *Player) void {
        const p: *Player = (self.players.fetchRemove(player.id) orelse @panic("Attempted to remove unmanaged player!")).value;
        p.deinit();
        self.allocator.destroy(p);
    }
};
