const std = @import("std");

// 1 MiB limit file size
const MAX_FILE_SIZE = 1024 * 1024;

const ArgError = error{
    NotaNumber,
    NoValueAfter,
    NoFilePath,
    NotOctet,
    InitError,
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var cli = Cli.new(allocator, std.io.getStdOut().writer());
    try cli.run();
}

const Cli = struct {
    alloc: std.mem.Allocator,
    args: ?Args,
    writer: std.fs.File.Writer,

    pub fn new(allocator: std.mem.Allocator, writer: anytype) Cli {
        return .{ .alloc = allocator, .args = null, .writer = writer };
    }

    pub fn run(self: *Cli) !void {
        const args: Args = Args.init(self.alloc) catch |err| {
            switch (err) {
                // TODO: treat errors properly
                ArgError.NoFilePath => {
                    std.debug.print("No file path given! Read the Docs.", .{});
                },
                else => {
                    std.debug.print("Something went wrong!", .{});
                },
            }
            std.process.exit(0);
        };
        self.args = args;
        // TODO: handle error
        const file_contents = try self.load();

        const limit = args.read_limit orelse file_contents.len;
        try self.display_contents(file_contents[0..limit]);
    }

    fn load(self: *Cli) ![]u8 {
        return try std.fs.cwd().readFileAlloc(self.alloc, self.args.?.file_path, MAX_FILE_SIZE);
    }

    fn display_contents(
        self: *Cli,
        contents: []const u8,
    ) !void {
        const row_size = self.args.?.num_cols;
        var start: usize = 0;
        var end: usize = row_size;
        while (start < contents.len) {
            try self.display_offset(start);

            const row = contents[start..end];

            try self.display_row(contents[start..end]);

            std.debug.print("{d}", .{row_size - (end - start)});
            try self.display_text(row);

            try self.writer.print("\n", .{});
            start = end;
            end = if (end + row_size <= contents.len) row_size + end else contents.len;
        }
    }

    fn display_text(self: *Cli, chunck: []const u8) !void {
        for (chunck) |byte| {
            try self.writer.print("{c}", .{if (byte != 0) byte else '.'});
        }
    }

    fn display_offset(self: *Cli, offset: usize) !void {
        if (self.args.?.offset_decimal) {
            try self.writer.print("{d:0>8}: ", .{offset});
        } else {
            try self.writer.print("{x:0>8}: ", .{offset});
        }
    }

    fn display_row(self: *Cli, chunck: []const u8) !void {
        var start_group: usize = 0;
        var end_group: usize = self.args.?.group_size;

        while (start_group < end_group) {
            const group = chunck[start_group..end_group];
            // TODO: this is ugly, but works for now
            if (self.args.?.little_endian) {
                var idx: usize = group.len;
                while (idx != 0) {
                    idx -= 1;
                    try self.writer.print("{x:0>2}", .{group[idx]});
                }
            } else {
                for (group) |byte| {
                    try self.writer.print("{x:0>2}", .{byte});
                }
            }

            try self.writer.print(" ", .{});

            start_group = end_group;
            end_group = if (end_group + self.args.?.group_size <= chunck.len) end_group + self.args.?.group_size else chunck.len;
        }
    }
};

const Args = struct {
    file_path: [:0]const u8,
    group_size: u8 = 2,
    little_endian: bool,
    read_limit: ?usize,
    offset_decimal: bool,
    num_cols: u8,

    /// Handle Cli Arguments
    pub fn init(allocator: std.mem.Allocator) ArgError!Args {
        var args = try std.process.argsWithAllocator(allocator);
        _ = args.skip(); // remove exe path

        var little_endian = false;
        var group_size: u8 = 0;
        var file_path: ?[:0]const u8 = undefined;
        var read_limit: ?usize = null;
        var offset_decimal = false;
        var num_cols: u8 = 16;

        while (args.next()) |arg| {
            if (std.mem.eql(u8, arg, "-e")) {
                little_endian = true;
                if (group_size == 0) {
                    group_size = 4;
                    // Check if group_size is a power of 2
                } else if (group_size <= 16 and (group_size & (group_size - 1)) == 0) {
                    return ArgError.NotOctet;
                }
            } else if (std.mem.eql(u8, arg, "-g")) {
                const buf = args.next() orelse return ArgError.NoValueAfter;
                group_size = std.fmt.parseUnsigned(u8, buf, 10) catch return ArgError.NotaNumber;
            } else if (std.mem.eql(u8, arg, "-l")) {
                const buf = args.next() orelse return ArgError.NoValueAfter;
                read_limit = std.fmt.parseUnsigned(usize, buf, 10) catch return ArgError.NotaNumber;
            } else if (std.mem.eql(u8, arg, "-d")) {
                offset_decimal = true;
            } else if (std.mem.eql(u8, arg, "-c")) {
                const buf = args.next() orelse return ArgError.NoValueAfter;
                num_cols = std.fmt.parseUnsigned(u8, buf, 10) catch return ArgError.NotaNumber;
            } else {
                file_path = arg;
            }
        }

        return .{
            .file_path = file_path orelse return ArgError.NoFilePath,
            .little_endian = little_endian,
            .group_size = if (group_size == 0) 2 else group_size,
            .read_limit = read_limit,
            .offset_decimal = offset_decimal,
            .num_cols = num_cols,
        };
    }
};
