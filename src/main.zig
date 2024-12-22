const std = @import("std");
const Cli = @import("cli").Cli;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const writer = std.io.getStdOut().writer();

    var cli = Cli.new(allocator, writer);
    // TODO: Handle with writer fails
    try cli.run();
}
