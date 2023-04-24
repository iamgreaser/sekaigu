pub const std = @import("std");
pub const log = std.log.scoped(.main);

pub const fs = std.fs;
pub const io = std.io;
pub const mem = std.mem;

pub const Allocator = std.mem.Allocator;
pub const ArrayList = std.ArrayList;
pub const ArrayListUnmanaged = std.ArrayListUnmanaged;
pub const StringArrayHashMapUnmanaged = std.StringArrayHashMapUnmanaged;
pub const FixedBufferStream = std.io.FixedBufferStream;

pub const std_options = struct {
    pub const log_level = .debug;
};

/// Maximum size of an XML node in bytes until we decide it's too long.
const MAX_NODE_SIZE_BYTES = 1024 * 64;

/// XML whitespace characters to be fed into the mem.trim* functions.
const XML_WHITESPACE = " \r\n\t";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    {
        var apigen = APIGen{ .allocator = allocator };
        defer ({
            log.info("Deinitialising the API generator state...", .{});
            apigen.deinit();
        });

        try parseKhronosXML(allocator, &apigen, "indat/glapi/gl.xml");

        {
            var base_writer = io.getStdOut().writer();
            var buffered_writer = io.bufferedWriter(base_writer);
            var writer = buffered_writer.writer();
            try apigen.generateFileBody(writer);
            try buffered_writer.flush();
        }
    }

    if (gpa.detectLeaks()) {
        log.err("Memory leak detected, fix it!", .{});
        return error.MemoryLeaked;
    }
}

pub const TagName = enum(u8) {
    const Self = @This();
    comment,
    registry,
    types,
    type,
    name,
    apientry,
    enums,
    @"enum",
    unused,
    commands,
    command,
    proto,
    param,
    ptype,
    glx,
    alias,
    vecequiv,
    feature,
    require,
    remove,
    extensions,
    extension,

    pub fn fromString(str: []const u8) !Self {
        inline for (@typeInfo(Self).Enum.fields) |field| {
            if (mem.eql(u8, str, field.name)) return @field(Self, field.name);
        }
        log.err("invalid enum string \"{s}\"", .{str});
        return error.EnumNotFound;
    }
};

pub const AttrName = enum(u8) {
    const Self = @This();
    name,
    comment,
    requires,
    namespace,
    group,
    type,
    value,
    start,
    end,
    alias,
    vendor,
    api,
    opcode,
    class,
    len,
    number,
    profile,
    supported,

    pub fn fromString(str: []const u8) !Self {
        inline for (@typeInfo(Self).Enum.fields) |field| {
            if (mem.eql(u8, str, field.name)) return @field(Self, field.name);
        }
        log.err("invalid enum string \"{s}\"", .{str});
        return error.EnumNotFound;
    }
};

pub const Attr = struct {
    name: AttrName,
    value: []u8,
};
pub const NodeUnion = union(enum) {
    Text: []u8,
    Tag: struct {
        name: TagName,
        attrs: ArrayListUnmanaged(Attr) = .{},
        children: ArrayListUnmanaged(*Node) = .{},
    },
};
pub const Node = struct {
    const Self = @This();
    parent: ?*Self,
    n: NodeUnion,

    pub fn pushNewAny(stack: *?*Self, allocator: Allocator, n: NodeUnion) !*Self {
        //log.debug("Pushing node {?*} {any}", .{ stack.*, n });
        if (stack.*) |parent| {
            if (parent.n != .Tag) {
                return error.PushedNodeOntoTerminal;
            }
        } else {
            if (n != .Tag) {
                return error.PushedTerminalOntoNull;
            }
        }
        const result = try allocator.create(Self);
        errdefer allocator.destroy(result);
        result.* = .{
            .parent = stack.*,
            .n = n,
        };
        if (result.parent) |parent| {
            try parent.n.Tag.children.append(allocator, result);
        }
        stack.* = result;
        return result;
    }

    pub fn addNewText(stack: *?*Self, allocator: Allocator, text: []const u8) !*Self {
        const owned_text = try allocator.dupe(u8, text);
        errdefer allocator.free(owned_text);
        const result = try pushNewAny(stack, allocator, .{ .Text = owned_text });
        errdefer @panic("Not sure how to handle an error here!");
        try removeTop(stack, allocator);
        return result;
    }

    pub fn pushNewTag(stack: *?*Self, allocator: Allocator, name: TagName) !*Self {
        return pushNewAny(stack, allocator, .{ .Tag = .{ .name = name } });
    }

    pub fn removeTop(stack: *?*Self, allocator: Allocator) !void {
        if (stack.*) |top| {
            stack.* = top.parent;
            if (top.parent == null) {
                log.info("Deallocating node tree, this may take a while...", .{});
                top.freeWithChildren(allocator);
            }
        }
    }

    /// Frees ourselves and our children.
    pub fn freeWithChildren(self: *Self, allocator: Allocator) void {
        switch (self.n) {
            .Text => |n| {
                allocator.free(n);
            },
            .Tag => |*n| {
                for (n.attrs.items) |attr| {
                    allocator.free(attr.value);
                }
                n.attrs.deinit(allocator);
                for (n.children.items) |child| {
                    child.freeWithChildren(allocator);
                }
                n.children.deinit(allocator);
            },
        }
        allocator.destroy(self);
    }

    /// Frees an entire stack of nodes.
    pub fn freeStack(self: *Self, allocator: Allocator) void {
        // Find the root
        var root: *Self = self;
        while (root.parent) |parent| root = parent;
        // Now deallocate everything!
        log.info("Deallocating incomplete node tree, this may take a while...", .{});
        root.freeWithChildren(allocator);
    }

    pub fn getChildText(self: *const Self) ![]const u8 {
        // We need the *child* text. If we are the text, this is the wrong thing to call.
        if (self.n == .Text) return error.NotASimpleTextNode;

        const children = &self.n.Tag.children;
        if (children.items.len != 1) return error.NotASimpleTextNode;
        if (children.items[0].n != .Text) return error.NotASimpleTextNode;

        return children.items[0].n.Text;
    }
};

fn parseKhronosXML(allocator: Allocator, apigen: *APIGen, in_fname: []const u8) !void {
    var file = try fs.cwd().openFile(in_fname, .{ .mode = .read_only });
    defer file.close();
    var buffered_reader = io.bufferedReader(file.reader());
    const reader = buffered_reader.reader();
    var reader_buf: [MAX_NODE_SIZE_BYTES]u8 = undefined;

    var node_stack: ?*Node = null;
    defer if (node_stack) |node| node.freeStack(allocator);

    // Any text before a tag?
    while (true) {
        if (try reader.readUntilDelimiterOrEof(&reader_buf, '<')) |rawtext| {
            var data: []const u8 = rawtext;

            // If we have a bomb at the start of the file, defuse it.
            if (mem.eql(u8, rawtext, "\xEF\xBB\xBF")) data = data[3..];

            // Strip whitespace because lol XML
            data = mem.trim(u8, data, XML_WHITESPACE);

            if (data.len >= 1) {
                //log.debug("*TEXT*: {d:>6} [{s}]", .{ data.len, data });
                _ = try Node.addNewText(&node_stack, allocator, data);
            }
        } else {
            // Reached EOF
            return;
        }

        if (try reader.readUntilDelimiterOrEof(&reader_buf, '>')) |rawtext| {
            var data: []const u8 = rawtext;

            // Work out what kind of tag we're dealing with
            if (data.len < 1) return error.InvalidFileFormat;
            switch (data[0]) {
                // XML directive. We're lazy, so we strip these.
                '?' => {},

                // SGML directive. This always ends up being a comment in OpenGL.
                // Unfortunately, we actually need to find the terminator for real.
                '!' => {
                    if (!mem.endsWith(u8, data, "--")) {
                        //log.debug("EVIL COMMENT {d:>6} [{s}]", .{ data.len, data });
                        // Welp, we have an evil comment.
                        // Scan until we find two hyphens.
                        // And no, the hyphens at the end don't count, as they have been cut short by a greater-than symbol.
                        var hyphens: u8 = 0;
                        while (true) {
                            const c = try reader.readByte();
                            if (c == '>' and hyphens >= 2) break;
                            if (c == '-') hyphens += 1 else hyphens = 0;
                        }
                    }
                },

                // Closing tag.
                '/' => {
                    data = data[1..];
                    const tagname = try TagName.fromString(data);
                    //log.debug("close:  {}", .{tagname});
                    if (node_stack) |node| {
                        if (node.n != .Tag) @panic("This shouldn't happen!");
                        if (node.n.Tag.name != tagname) {
                            log.err("Closing tag {} does not match opening tag {}", .{ tagname, node.n.Tag.name });
                            return error.TagMismatch;
                        }
                        try apigen.handleTagNode(node_stack.?);
                        try Node.removeTop(&node_stack, allocator);
                    } else {
                        return error.Overflow;
                    }
                },

                // Opening tag OR singleton tag.
                else => {
                    const singleton = (data[data.len - 1] == '/');
                    if (singleton) {
                        data = mem.trimRight(u8, data[0 .. data.len - 1], XML_WHITESPACE);
                    }

                    var spaceiter = mem.split(u8, data, " ");
                    const rawtagname = spaceiter.first();
                    const tagname = try TagName.fromString(rawtagname);
                    const node: *Node = try Node.pushNewTag(&node_stack, allocator, tagname);

                    data = spaceiter.rest();
                    while (data.len >= 1) {
                        // WARNING: Assumes everything is key="value with maybe spaces in it"!
                        var kviter = mem.split(u8, data, "=\"");
                        const rawattrname = kviter.first();
                        const valuepart = kviter.rest();
                        var viter = mem.split(u8, valuepart, "\"");
                        const attrvalue = viter.first();
                        data = viter.rest();
                        data = mem.trimLeft(u8, data, XML_WHITESPACE);
                        const attrname = try AttrName.fromString(rawattrname);
                        //log.debug("attr    {} {d:>6} [{s}]", .{ attrname, attrvalue.len, attrvalue });
                        var pvalue = try allocator.dupe(u8, attrvalue);
                        errdefer allocator.free(pvalue);
                        try node.n.Tag.attrs.append(allocator, Attr{ .name = attrname, .value = pvalue });
                    }

                    //if (singleton) log.debug("single  {} {d:>6} [{s}]", .{ tagname, data.len, data });
                    //if (!singleton) log.debug("open:   {} {d:>6} [{s}]", .{ tagname, data.len, data });

                    if (singleton) {
                        try apigen.handleTagNode(node_stack.?);
                        try Node.removeTop(&node_stack, allocator);
                    }
                },
            }
        } else {
            // Reached EOF
            return;
        }
    }
}

const APICommand = struct {
    const Self = @This();
    name: []u8,
    type: []u8,
    params: ArrayListUnmanaged(APICommandParam),

    needs_linking: bool = false,
    needs_extension: bool = false,

    pub fn create(allocator: Allocator, name: []const u8, type_: []const u8) !*Self {
        var dupname = try allocator.dupe(u8, name);
        errdefer allocator.free(dupname);
        var duptype = try allocator.dupe(u8, type_);
        errdefer allocator.free(duptype);
        var result = try allocator.create(APICommand);
        errdefer @panic("Not sure how to clean up here! --GM");
        result.* = .{
            .name = dupname,
            .type = duptype,
            .params = .{},
        };
        return result;
    }

    pub fn destroy(self: *Self, allocator: Allocator) void {
        for (self.params.items) |*p| {
            p.deinit(allocator);
        }
        self.params.deinit(allocator);
        allocator.free(self.name);
        allocator.free(self.type);
        self.* = undefined;
        allocator.destroy(self);
    }

    pub fn printExternPrototype(self: *Self, writer: anytype) !void {
        try writer.print("pub extern fn {s} (", .{self.name});
        for (self.params.items, 0..) |*p, i| {
            if (i != 0) try writer.print(", ", .{});
            try writer.print("{s}: {s}", .{ p.name, p.type });
        }
        try writer.print(") {s};\n", .{self.type});
    }

    pub fn printFPField(self: *Self, writer: anytype) !void {
        try writer.print("    {s}: *const fn (", .{self.name});
        for (self.params.items, 0..) |*p, i| {
            if (i != 0) try writer.print(", ", .{});
            try writer.print("{s}: {s}", .{ p.name, p.type });
        }
        try writer.print(") callconv(.C) {s} = undefined,\n", .{self.type});
    }

    pub fn printFPWrapper(self: *Self, writer: anytype) !void {
        try writer.print("\npub fn {s} (", .{self.name});
        for (self.params.items, 0..) |*p, i| {
            if (i != 0) try writer.print(", ", .{});
            try writer.print("{s}: {s}", .{ p.name, p.type });
        }
        try writer.print(") callconv(.C) {s} {{\n", .{self.type});
        try writer.print("    return extensions.{s}(", .{self.name});
        for (self.params.items, 0..) |*p, i| {
            if (i != 0) try writer.print(", ", .{});
            try writer.print("{s}", .{p.name});
        }
        try writer.print(");\n", .{});
        try writer.print("}}\n", .{});
    }
};

const APICommandParam = struct {
    const Self = @This();
    name: []u8,
    type: []u8,

    pub fn init(allocator: Allocator, name: []const u8, type_: []const u8) !Self {
        var dupname = try allocator.dupe(u8, name);
        errdefer allocator.free(dupname);
        var duptype = try allocator.dupe(u8, type_);
        errdefer allocator.free(duptype);
        var result = Self{
            .name = dupname,
            .type = duptype,
        };
        return result;
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.type);
        self.* = undefined;
    }
};

const APIGen = struct {
    const Self = @This();

    allocator: Allocator,
    commands: StringArrayHashMapUnmanaged(*APICommand) = .{},

    pub fn deinit(self: *Self) void {
        var iter = self.commands.iterator();
        while (iter.next()) |kv| {
            // Calling destroy on v will also free v.name which is the same pointer as k
            // Because of this we don't need to (and MUST NOT) also free the key explicitly here
            kv.value_ptr.*.destroy(self.allocator);
        }
        self.commands.deinit(self.allocator);
    }

    pub fn generateFileBody(self: *Self, writer: anytype) !void {
        {
            var iter = self.commands.iterator();
            while (iter.next()) |kv| {
                var command = kv.value_ptr.*;
                if (command.needs_linking and command.needs_extension) try command.printExternPrototype(writer);
            }
        }
        try writer.print("\n", .{});
        try writer.print("pub var extensions: struct {{\n", .{});
        {
            var iter = self.commands.iterator();
            while (iter.next()) |kv| {
                var command = kv.value_ptr.*;
                if (command.needs_extension and !command.needs_linking) try command.printFPField(writer);
            }
        }
        try writer.print("}} = .{{}};\n", .{});
        {
            var iter = self.commands.iterator();
            while (iter.next()) |kv| {
                var command = kv.value_ptr.*;
                if (command.needs_extension and !command.needs_linking) try command.printFPWrapper(writer);
            }
        }
    }

    pub fn handleTagNode(self: *Self, node: *Node) !void {
        // TODO! --GM
        switch (node.n) {
            .Text => @panic("We don't handle text nodes here!"),
            .Tag => |n| {
                switch (n.name) {
                    .command => if (node.parent) |parent| {
                        switch (parent.n.Tag.name) {
                            .commands => {
                                // Definition for a command
                                try self.handleCommandDef(node);
                            },

                            .require => {
                                // Use of a command
                                if (parent.parent == null) {
                                    log.err("nonexistent parent for <require><command>", .{});
                                    return error.SchemaViolation;
                                }
                                switch (parent.parent.?.n.Tag.name) {
                                    .feature => {
                                        try self.handleCommandUse(parent.parent.?, node);
                                    },

                                    // TODO: Consider dumpster-diving through extensions --GM
                                    .extension => {},

                                    else => |name| {
                                        log.err("invalid parent for <require><command>: {}", .{name});
                                        return error.SchemaViolation;
                                    },
                                }
                            },

                            .remove => {},

                            else => |name| {
                                log.err("invalid parent for <command>: {}", .{name});
                                return error.SchemaViolation;
                            },
                        }
                    },

                    else => {},
                }
            },
        }
    }

    fn handleCommandUse(self: *Self, parentparent: *Node, node: *Node) !void {
        const ppn = &parentparent.n.Tag;
        const n = &node.n.Tag;

        // Work out what this is for
        var feature_name: ?[]const u8 = null;
        for (ppn.attrs.items) |attr| {
            switch (attr.name) {
                .name => feature_name = attr.value,
                else => {},
            }
        }

        if (feature_name == null) {
            log.err("no name in feature node", .{});
            return error.SchemaViolation;
        }

        // Detect if it's an extension and boot it out if we aren't using it
        const is_extension = if (mem.eql(u8, "GL_VERSION_1_0", feature_name.?))
            false
        else if (mem.eql(u8, "GL_VERSION_1_1", feature_name.?))
            false
        else if (mem.eql(u8, "GL_ES_VERSION_2_0", feature_name.?))
            true
        else
            return;

        // Get the node name
        var node_name: ?[]const u8 = null;
        for (n.attrs.items) |attr| {
            switch (attr.name) {
                .name => node_name = attr.value,
                else => {},
            }
        }
        if (node_name == null) {
            log.err("no name in command/enum/type node", .{});
            return error.SchemaViolation;
        }

        // Get the command
        var command = self.commands.get(node_name.?) orelse {
            log.err("referenced command \"{s}\" not defined as a command", .{node_name.?});
            return error.SchemaViolation;
        };

        // Indicate that we use this node
        if (is_extension) {
            command.needs_extension = true;
        } else {
            command.needs_linking = true;
        }
    }

    fn handleCommandDef(self: *Self, node: *Node) !void {
        // Look through our nodes
        const n = &node.n.Tag;
        var command: ?*APICommand = null;
        errdefer if (command) |c| c.destroy(self.allocator);

        for (n.children.items) |child| {
            if (child.n == .Text) continue;
            const cn = &child.n.Tag;
            switch (cn.name) {
                inline .proto, .param => |ptype| {
                    var tname: ?[]const u8 = null;
                    var ttype: ?[]const u8 = null;
                    var ttypesuffix: []const u8 = "";
                    var isconst: bool = false;
                    for (cn.children.items) |cchild| switch (cchild.n) {
                        .Text => |s| {
                            if (ttype == null) {
                                if (mem.eql(u8, s, "void")) {
                                    ttype = "void";
                                } else if (mem.eql(u8, s, "const")) {
                                    isconst = true;
                                } else if (mem.eql(u8, s, "const void *")) {
                                    isconst = true;
                                    ttype = "void";
                                    ttypesuffix = "*";
                                } else if (mem.eql(u8, s, "const void **")) {
                                    isconst = true;
                                    ttype = "void";
                                    ttypesuffix = "**";
                                } else if (mem.eql(u8, s, "void *")) {
                                    ttype = "void";
                                    ttypesuffix = "*";
                                    ttype = "*void";
                                } else if (mem.eql(u8, s, "void **")) {
                                    ttype = "void";
                                    ttypesuffix = "**";
                                } else if (mem.eql(u8, s, "const void *const*")) {
                                    isconst = true;
                                    ttype = "void";
                                    ttypesuffix = "*const*";
                                } else {
                                    log.err("TODO: Type text prefix node \"{s}\"", .{s});
                                    return error.SchemaViolation;
                                }
                            } else {
                                if (mem.eql(u8, s, "*")) {
                                    ttypesuffix = "*";
                                } else if (mem.eql(u8, s, "**")) {
                                    ttypesuffix = "**";
                                } else if (mem.eql(u8, s, "*const*")) {
                                    ttypesuffix = "*const*";
                                } else {
                                    log.err("TODO: Type text suffix node \"{s}\"", .{s});
                                    return error.SchemaViolation;
                                }
                            }
                        },
                        .Tag => |ccn| {
                            switch (ccn.name) {
                                .name => {
                                    if (tname != null) {
                                        log.err("Attempted to clobber name \"{s}\"", .{tname.?});
                                        return error.SchemaViolation;
                                    }
                                    tname = try cchild.getChildText();
                                },
                                .ptype => {
                                    if (ttype != null) {
                                        log.err("Attempted to clobber type \"{s}\"", .{ttype.?});
                                        return error.SchemaViolation;
                                    }
                                    ttype = try cchild.getChildText();
                                },
                                else => {},
                            }
                        },
                    };

                    if (tname == null) {
                        log.err("no name in node", .{});
                        return error.SchemaViolation;
                    }
                    if (ttype == null) {
                        log.err("no type computed in node", .{});
                        return error.SchemaViolation;
                    }

                    var combined_type_buf: [128]u8 = undefined;
                    var combined_type = try std.fmt.bufPrint(
                        &combined_type_buf,
                        "{s}{s}{s}",
                        .{
                            ttypesuffix,
                            if (isconst) "const " else "",
                            ttype.?,
                        },
                    );

                    switch (ptype) {
                        .proto => {
                            if (command != null) {
                                log.err("two proto tags used", .{});
                                return error.SchemaViolation;
                            }
                            command = try APICommand.create(
                                self.allocator,
                                tname.?,
                                combined_type,
                            );
                        },

                        .param => {
                            if (command) |cmd| {
                                try cmd.params.append(self.allocator, try APICommandParam.init(
                                    self.allocator,
                                    tname.?,
                                    combined_type,
                                ));
                            } else {
                                log.err("param came before proto", .{});
                                return error.SchemaViolation;
                            }
                        },

                        else => @compileError("unreachable"),
                    }
                },

                else => {},
            }
        }
        if (command) |cmd| {
            try self.commands.putNoClobber(self.allocator, cmd.name, cmd);
            errdefer ({
                // Key is owned by command, not by hashmap.
                if (self.commands.fetchRemove(cmd.name)) |c| {
                    _ = c;
                } else {
                    log.err("CLEANUP BORKED: \"{s}\" wasn't inserted into the commands map!", .{cmd.name});
                }
            });
        } else {
            log.err("no proto node", .{});
            return error.SchemaViolation;
        }
    }
};
