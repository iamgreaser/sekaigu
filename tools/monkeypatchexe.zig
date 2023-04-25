// If you want this to run on anything earlier than Windows Vista, you need to monkey-patch the executable. Even though Zig allows you to use an older ABI and/or API. Yes, this is utterly stupid. --GM
// WARNING: THIS CAN ONLY SAFELY MONKEY-PATCH A 32-BIT EXECUTABLE. FOR SOME GENEROUS DEFINITION OF "SAFELY". IT WILL PROBABLY BREAK IF YOU DO IT TO A 64-BIT EXECUTABLE! --GM
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    var file = try std.fs.cwd().openFile(args[1], .{ .mode = .read_write });
    defer file.close();
    try file.seekTo(0xB8);
    try file.writeAll("\x04");
    try file.seekTo(0xC0);
    try file.writeAll("\x04");
}
