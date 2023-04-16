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

const schema = @import("schema.zig");

const WebClientState = if (builtin.target.isWasm())
    struct {}
else
    @import("WebServer.zig").ClientState;

pub const PlayerType = union(enum) {
    Local: *LocalPlayer,
    WebClient: *WebClientState,
};

pub const LocalPlayer = struct {
    // TODO! --GM
};

const MAX_PLAYERS = 1000;
pub const Player = struct {
    const Self = @This();
    pub const Id = u16;
    pub const InitOptions = struct {
        player_type: PlayerType,
    };
    pub const State = struct {
        pub const SCHEMA = .{ "pos", "rot", "dpos", "drot" };
        pos: Vec4f = Vec4f.new(.{ 0.0, 0.0, 0.0, 1.0 }),
        rot: Vec4f = Vec4f.new(.{ 0.0, 0.0, 0.0, 1.0 }),
        dpos: Vec4f = Vec4f.new(.{ 0.0, 0.0, 0.0, 0.0 }),
        drot: Vec4f = Vec4f.new(.{ 0.0, 0.0, 0.0, 0.0 }),
    };
    pub const SCHEMA = .{ "id", "state" };

    session: *Session,
    player_type: PlayerType,

    id: Id,
    state: State = .{},

    pub const Events = struct {
        pub const SetPos = struct {
            const EV = @This();
            pos: Vec4f,
            pub fn init(pos: Vec4f) !EV {
                return EV{ .pos = pos };
            }
            pub fn apply(ev: *const EV, player: *Self) !void {
                player.state.pos = ev.pos;
            }
        };
        pub const SetRot = struct {
            const EV = @This();
            rot: Vec4f,
            pub fn init(rot: Vec4f) !EV {
                return EV{ .rot = rot };
            }
            pub fn apply(ev: *const EV, player: *Self) !void {
                player.state.rot = ev.rot;
            }
        };
        pub const SetDPos = struct {
            const EV = @This();
            dpos: Vec4f,
            pub fn init(dpos: Vec4f) !EV {
                return EV{ .dpos = dpos };
            }
            pub fn apply(ev: *const EV, player: *Self) !void {
                player.state.dpos = ev.dpos;
            }
        };
        pub const SetDRot = struct {
            const EV = @This();
            drot: Vec4f,
            pub fn init(drot: Vec4f) !EV {
                return EV{ .drot = drot };
            }
            pub fn apply(ev: *const EV, player: *Self) !void {
                player.state.drot = ev.drot;
            }
        };
    };

    pub fn init(self: *Self, session: *Session, id: Self.Id, options: InitOptions) !void {
        log.info("Creating player", .{});
        self.* = .{
            .session = session,
            .id = id,
            .player_type = options.player_type,
        };
        log.info("Player created", .{});
    }

    pub fn getCurrentState(self: *const Self) State {
        return self.state;
    }

    pub fn getPredictedState(self: *const Self, dt: f32) State {
        var state = self.state;
        const icam = Mat4f.I
            .translate(state.pos.a[0], state.pos.a[1], state.pos.a[2])
            .rotate(-state.rot.a[1], 0.0, 1.0, 0.0)
            .rotate(-state.rot.a[0], 1.0, 0.0, 0.0);
        state.pos = state.pos.add(icam.mul(state.dpos.mul(dt)));
        state.rot = state.rot.add(state.drot.mul(dt));
        return state;
    }

    pub fn handleEvent(self: *Self, comptime TEvent: type, args: anytype) !void {
        var ev: TEvent = try @call(.auto, TEvent.init, args);
        try ev.apply(self);
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
    pub const State = struct {
        pub const SCHEMA = .{ "model_zrot", "model_dzrot" };
        model_zrot: f32 = 0.0,
        model_dzrot: f32 = 3.141593 * 2.0 / 5.0,
    };
    pub const SCHEMA = .{ "state", "players" };

    pub const Events = struct {
        pub const SetZRot = struct {
            const EV = @This();
            rot: f32,
            pub fn init(rot: f32) !EV {
                return EV{ .rot = rot };
            }
            pub fn apply(ev: *const EV, session: *Self) !void {
                session.state.model_zrot = ev.rot;
            }
        };
    };

    players: AutoHashMap(Player.Id, *Player),
    player_ids_used: [MAX_PLAYERS]bool = [1]bool{false} ** MAX_PLAYERS,
    state: State = .{},

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

    pub fn saveAlloc(self: *Self, allocator: Allocator) ![]u8 {
        var albuf = std.ArrayList(u8).init(allocator);
        defer albuf.deinit();
        var writer = albuf.writer();
        try schema.save(@TypeOf(writer), &writer, Self, self);
        log.info("Saved session: {d} bytes", .{albuf.items.len});
        var result = try albuf.toOwnedSlice();
        errdefer allocator.free(result);
        return result;
    }

    pub fn loadFromMemory(self: *Self, buf: []const u8) !void {
        // TODO! --GM
        _ = self;
        _ = buf;
        return error.TODO;
    }

    pub fn getCurrentState(self: *const Self) State {
        return self.state;
    }

    pub fn getPredictedState(self: *const Self, dt: f32) State {
        var state = self.state;
        state.model_zrot += state.model_dzrot * dt;
        return state;
    }

    pub fn handleEvent(self: *Self, comptime TEvent: type, args: anytype) !void {
        var ev: TEvent = try @call(.auto, TEvent.init, args);
        try ev.apply(self);
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
