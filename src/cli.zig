const std = @import("std");
const argp = @import("args_parse");

const version_string = "zxd 2024-07-11 by Caio Bernardo.";

// TODO: To implement
const help_string =
    \\Usage:
    \\	zxd [options] [infile]
    \\Options:
    \\	-a          toggle autoskip: nul-lines are not displayed. Default off.
    // \\	-b          binary digit dump (incompatible with -ps,-i,-r). Default hex.
    // \\	-C          capitalize variable names in C include file style (-i).
    \\	-c cols     format <cols> octets per line. Default 16 (-i: 12, -ps: 30).
    // \\	-E          show characters in EBCDIC. Default ASCII.
    \\	-e          little-endian dump (incompatible with -ps,-i,-r).
    \\	-g bytes    number of octets per group in normal output. Default 2 (-e: 4).
    \\	-h          print this summary.
    // \\	-i          output in C include file style.
    \\	-l len      stop after <len> octets.
    \\	-o off      add <off> to the displayed file position.
    // \\	-ps         output in postscript plain hexdump style.
    \\	-r          reverse operation: convert (or patch) hexdump into binary.
    // \\	-r -s off   revert with <off> added to file positions found in hexdump.
    \\	-d          show offset in decimal instead of hex.
    \\	-s seek     start at <seek> bytes abs.  
    \\	-u          use upper case hex letters.
    \\	-v          show version: "zxd 2024-07-11 by Caio Bernardo.".
;

// 1 MiB limit file size
const MAX_FILE_SIZE = 1024 * 1024;

pub const Cli = struct {
    alloc: std.mem.Allocator,
    args: argp.Args = undefined,
    writer: std.fs.File.Writer,

    pub fn new(allocator: std.mem.Allocator, writer: anytype) Cli {
        return .{ .alloc = allocator, .writer = writer };
    }

    pub fn run(self: *Cli) !void {
        const args: argp.Args = argp.Args.init(self.alloc) catch |err| {
            switch (err) {
                // TODO: treat errors properly
                argp.ArgError.NoFilePath => {
                    try self.writer.print("No file path given! Read the Docs.", .{});
                },
                argp.ArgError.HelpString => {
                    try self.writer.print(help_string, .{});
                },
                argp.ArgError.VersionString => {
                    try self.writer.print(version_string, .{});
                },
                else => {
                    std.debug.print("Failed to parse arguments: {}. Check the docs!", .{err});
                },
            }
            std.process.exit(0);
        };

        self.args = args;
        // TODO: handle error
        const file_contents = try self.load_file();

        if (self.args.revert) {
            try self.hex_to_bin(file_contents);
        } else {
            const limit = @min(args.read_limit orelse file_contents.len, file_contents.len);
            const start = self.args.seek;
            const end = @min(limit, limit + self.args.seek);
            // TODO: handle this error
            try self.dump_fmt_lines(file_contents[start..end]);
        }
    }

    fn load_file(self: *Cli) ![]u8 {
        return try std.fs.cwd().readFileAlloc(self.alloc, self.args.file_path, MAX_FILE_SIZE);
    }

    fn hex_to_bin(self: *Cli, contents: []const u8) !void {
        // Read per line
        var lines = std.mem.tokenizeAny(u8, contents, "\n");
        while (lines.next()) |line| {
            // Split by the offset mark
            var parts = std.mem.tokenizeAny(u8, line, ":");
            _ = parts.next(); // Remove offset
            var group = std.mem.tokenizeSequence(u8, parts.next() orelse continue, "  "); // Split by hex and text section
            var hexes = std.mem.tokenizeAny(u8, group.next() orelse continue, " "); // Split group section in its group of hexes
            var out: [32:0]u8 = undefined;
            while (hexes.next()) |hexstr| {
                try self.writer.print("{s}", .{try std.fmt.hexToBytes(&out, hexstr)});
            }
        }
    }

    fn dump_fmt_lines(self: *Cli, contents: []const u8) !void {
        var lines = std.mem.window(u8, contents, self.args.row_len, self.args.row_len);
        var line_id: usize = 0;
        while (lines.next()) |line| {
            line_id += 1;
            if (self.args.autoskip and std.mem.allEqual(u8, line, 0)) {
                continue;
            }
            try self.display_offset((line_id - 1) * self.args.row_len + self.args.seek);

            var groups = std.mem.window(u8, line, self.args.group_size, self.args.group_size);
            while (groups.next()) |group| {
                try self.display_group(group);
            }

            try self.spacing(line.len);

            self.display_text(line) catch std.debug.print("Failed to print line", .{});
            try self.writer.print("\n", .{});
        }
    }

    fn print_as_hex(self: *Cli, byte: u8) !void {
        if (self.args.upperhex) {
            try self.writer.print("{X:0>2}", .{byte});
        } else {
            try self.writer.print("{x:0>2}", .{byte});
        }
    }

    fn spacing(self: *Cli, line_length: usize) !void {
        for (1..(self.args.row_len - line_length + 2)) |i| {
            try self.writer.print("{c: >2}", .{' '});
            if (i % self.args.group_size == 0) {
                try self.writer.print(" ", .{});
            }
        }
    }

    fn display_text(self: *Cli, chunck: []const u8) !void {
        for (chunck) |byte| {
            try self.writer.print("{c}", .{if (byte != 0) byte else '.'});
        }
    }

    fn display_offset(self: *Cli, offset: usize) !void {
        if (self.args.offset_decimal) {
            try self.writer.print("{d:0>8}: ", .{offset + self.args.offset});
        } else {
            try self.writer.print("{x:0>8}: ", .{offset + self.args.offset});
        }
    }

    fn display_group(self: *Cli, group: []const u8) !void {
        // if little endian revert group
        if (self.args.little_endian) {
            var iter = std.mem.reverseIterator(group);
            while (iter.next()) |byte| {
                try self.print_as_hex(byte);
            }
        } else {
            for (group) |byte| {
                try self.print_as_hex(byte);
            }
        }

        try self.writer.print(" ", .{});
    }
};
