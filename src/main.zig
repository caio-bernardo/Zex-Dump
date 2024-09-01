const std = @import("std");

// Max bytes to read from a file
const MAX_BYTES = 1_000_000;

const ArgError = error{
    NotaNumber,
    NoValueAfter,
    NoFilePath,
    NotOctet,
    InitError,
};

const Args = struct {
    file_path: [:0]const u8,
    group_size: u8 = 2,
    little_endian: bool,
    read_limit: ?usize,
    offset_decimal: bool,
    num_cols: u8,
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const args: Args = handle_args(allocator) catch |err| {
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

    // TODO: handle this error
    const contents = try std.fs.cwd().readFileAlloc(allocator, args.file_path, MAX_BYTES);

    const limit = if (args.read_limit != null) args.read_limit.? else contents.len;
    display_contents(
        contents[0..limit],
        args.num_cols,
        args.group_size,
        args.little_endian,
        args.offset_decimal,
    );
}

fn display_contents(
    contents: []const u8,
    row_size: u8,
    group_size: u8,
    revert_groups: bool, // TODO: think of a better implementation of this
    off_set_decimal: bool,
) void {
    var start: usize = 0;
    var end: usize = row_size;
    while (start < contents.len) {
        display_offset(start, off_set_decimal);
        const row = contents[start..end];

        var start_group: usize = 0;
        var end_group: usize = group_size;

        while (start_group < end_group) {
            const group = row[start_group..end_group];
            // TODO: this is ugly, but works for now
            if (revert_groups) {
                var idx: usize = group.len;
                while (idx != 0) {
                    idx -= 1;
                    std.debug.print("{x:0>2}", .{group[idx]});
                }
            } else {
                for (group) |byte| {
                    std.debug.print("{x:0>2}", .{byte});
                }
            }

            // TODO: need to take into account that if a group is smaller than its size,
            // it should print more spaces to not break the indentation of display text
            std.debug.print(" ", .{});

            start_group = end_group;
            end_group = if (end_group + group_size <= row.len) end_group + group_size else row.len;
        }

        display_as_text(row);
        std.debug.print("\n", .{});
        start = end;
        end = if (end + row_size <= contents.len) row_size + end else contents.len;
    }
}

test "display-contents-test" {
    const bytes = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31 };
    const limit = bytes.len;
    display_contents(bytes[0..limit], 8, 2);
    std.debug.print("\n\n", .{});
}

/// Handle Cli Arguments
pub fn handle_args(allocator: std.mem.Allocator) ArgError!Args {
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

fn display_as_text(bytes: []const u8) void {
    for (bytes) |byte| {
        std.debug.print("{c}", .{if (byte != 0) byte else '.'});
    }
}

fn display_offset(offset: usize, is_decimal: bool) void {
    // TODO: Solve this
    if (is_decimal) {
        std.debug.print("{d:0>8}: ", .{offset});
    } else {
        std.debug.print("{x:0>8}: ", .{offset});
    }
}
