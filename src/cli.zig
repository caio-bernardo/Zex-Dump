const std = @import("std");
const argp = @import("args_parse");

const version_string = "zxd 2024-07-11 by Caio Bernardo.";

// TODO: To implement
const help_string =
    \\Usage:
    \\	zxd [options] [infile]
    \\Options:
    // \\	-a          toggle autoskip: A single '*' replaces nul-lines.Default off.
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
    // \\	-r          reverse operation: convert (or patch) hexdump into binary.
    // \\	-r -s off   revert with <off> added to file positions found in hexdump.
    \\	-d          show offset in decimal instead of hex.
    \\	-s [+][-]seek  start at <seek> bytes abs. (or +: rel.) infile offset.
    \\	-u          use upper case hex letters.
    \\	-v          show version: "zxd 2024-07-11 by Caio Bernardo.".
;

// 1 MiB limit file size
const MAX_FILE_SIZE = 1024 * 1024;

pub const Cli = struct {
    alloc: std.mem.Allocator,
    args: ?argp.Args,
    writer: std.fs.File.Writer,

    pub fn new(allocator: std.mem.Allocator, writer: anytype) Cli {
        return .{ .alloc = allocator, .args = null, .writer = writer };
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
                    std.debug.print("Something went wrong!", .{});
                },
            }
            std.process.exit(0);
        };

        self.args = args;
        // TODO: handle error
        const file_contents = try self.load_file();

        // if (self.args.?.revert) try self.hex_to_bin(file_contents) else {
        const limit = args.read_limit orelse file_contents.len;
        // TODO: handle this error
        try self.display_contents(file_contents[(self.args.?.seek)..(limit + self.args.?.seek)]);
        // }
    }

    fn load_file(self: *Cli) ![]u8 {
        return try std.fs.cwd().readFileAlloc(self.alloc, self.args.?.file_path, MAX_FILE_SIZE);
    }

    fn display_contents(
        self: *Cli,
        contents: []const u8,
    ) !void {
        const row_size = if (self.args.?.row_len < contents.len) self.args.?.row_len else contents.len;
        var start: usize = 0;
        var end: usize = row_size;
        while (start < contents.len) {
            try self.display_offset(start + self.args.?.seek);

            const row = contents[start..end];

            try self.display_row(contents[start..end]);

            if (end - start < self.args.?.row_len) {
                const spaces = self.args.?.row_len - (end - start) + 1;
                for (1..spaces) |spacechar| {
                    try self.writer.print("{c: >2}", .{' '});
                    if (spacechar % self.args.?.group_size == 0) {
                        try self.writer.print(" ", .{});
                    }
                }
            }

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
            try self.writer.print("{d:0>8}: ", .{offset + self.args.?.offset});
        } else {
            try self.writer.print("{x:0>8}: ", .{offset + self.args.?.offset});
        }
    }

    fn display_row(self: *Cli, chunck: []const u8) !void {
        var start_group: usize = 0;
        var end_group: usize = if (self.args.?.group_size < chunck.len) self.args.?.group_size else chunck.len;

        while (start_group < end_group) {
            const group = chunck[start_group..end_group];
            // TODO: this is ugly, but works for now
            if (self.args.?.little_endian) {
                var idx: usize = group.len;
                while (idx != 0) {
                    idx -= 1;
                    if (self.args.?.upperhex) try self.writer.print("{X:0>2}", .{group[idx]}) else try self.writer.print("{x:0>2}", .{group[idx]});
                }
            } else {
                for (group) |byte| {
                    if (self.args.?.upperhex) try self.writer.print("{X:0>2}", .{byte}) else try self.writer.print("{x:0>2}", .{byte});
                }
            }

            try self.writer.print(" ", .{});

            start_group = end_group;
            end_group = if (end_group + self.args.?.group_size <= chunck.len) end_group + self.args.?.group_size else chunck.len;
        }
    }
};
