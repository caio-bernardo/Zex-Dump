const std = @import("std");

const MAX_BYTES = 1_000_000;

const ArgError = error{
    NoFilePath,
};

const Args = struct {
    file_path: [:0]const u8,
};

pub fn handle_args(allocator: std.mem.Allocator) !Args {
    var args = try std.process.argsWithAllocator(allocator);
    _ = args.skip();

    const parsed_args: Args = Args{ .file_path = args.next() orelse return ArgError.NoFilePath };
    return parsed_args;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const args: Args = handle_args(allocator) catch |err| {
        switch (err) {
            ArgError.NoFilePath => {
                std.debug.print("No file path given! Read the Docs.", .{});
            },
            else => {
                std.debug.print("Something went wrong!", .{});
            },
        }
        std.process.exit(0);
    };

    const contents = try std.fs.cwd().readFileAlloc(allocator, args.file_path, MAX_BYTES);

    const chunck_size = 16;
    const chunks_count = contents.len / chunck_size + 1;

    for (1..chunks_count) |num| {
        const end = num * chunck_size;
        const start = end - chunck_size;

        std.debug.print("{x:0>8}: ", .{start});
        for (contents[start..end], 1..) |byte, idx| {
            std.debug.print("{x:0<2}", .{byte});
            const sep = if (idx % 2 == 0) " " else "";
            std.debug.print("{s}", .{sep});
        }

        for (contents[start..end]) |byte| {
            std.debug.print("{c}", .{if (byte != 0) byte else '.'});
        }
        std.debug.print("\n", .{});
    }
    // TODO: Implement other functionalities

}
