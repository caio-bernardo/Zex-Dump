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

    // TODO: calculate group_size considering row size
    const groups_max = if (args.group_size > args.num_cols) args.num_cols else args.group_size;
    const groups = try dump(allocator, contents, args.read_limit, groups_max);
    defer {
        for (groups) |group| {
            allocator.free(group);
        }
        allocator.free(groups);
    }

    display_groups(groups, args);
}

pub fn display_groups(groups: [][]u8, args: Args) void {
    const groups_per_row = args.num_cols / args.group_size;
    const rows = groups.len / groups_per_row;

    var end: u32 = groups_per_row;
    var start: u32 = 0;

    for (0..rows) |row_num| {
        display_offset((row_num) * args.num_cols, args.offset_decimal);

        if (args.little_endian) display_bytes_little_endian(groups[start..end]) else display_bytes(groups[start..end]);

        for (groups[start..end]) |group| {
            display_as_text(group);
        }

        std.debug.print("\n", .{});
        start = end;
        end += groups_per_row;
    }
}

fn display_contents(
    contents: []const u8,
    row_size: u8,
    group_size: u8,
) void {
    var start: usize = 0;
    var end: usize = row_size;
    while (start < contents.len) {
        std.debug.print("{x:0>8} ", .{start});
        const row = contents[start..end];
        for (row, 1..) |byte, read_count| {
            std.debug.print("{x:0>2}", .{byte});
            if (read_count % group_size == 0 or read_count == row.len) {
                std.debug.print(" ", .{});
            }
        }
        std.debug.print("bar...", .{});
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

/// Create a slice of slices of bytes, using `contents`, slice size defined by
/// `group_max_size` and stop reading bytes at `read_limit` if defined.
/// Caller owns the return data.
fn dump(
    allocator: std.mem.Allocator,
    contents: []const u8,
    read_limit: ?usize,
    group_max_size: usize,
) ![][]u8 {
    const limit = if (read_limit != null and read_limit.? <= contents.len) read_limit.? else contents.len;

    var group = try std.ArrayList(u8).initCapacity(allocator, group_max_size);
    errdefer group.deinit();

    var rows = std.ArrayList([]u8).init(allocator);
    errdefer rows.deinit();

    for (contents[0..limit], 1..) |byte, read_count| {
        try group.append(byte);
        if (group.items.len == group_max_size or read_count == limit) {
            try rows.append(try group.toOwnedSlice());
        }
    }

    return rows.toOwnedSlice();
}

test "dump-limit-fit-test" {
    const allocator = std.testing.allocator;
    const bytes = [_]u8{ 0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9, 0xa, 0xb, 0xc, 0xd, 0xe, 0xf };
    const rows = try dump(allocator, bytes[0..], 16, 4);
    defer {
        for (rows) |row| {
            allocator.free(row);
        }
        allocator.free(rows);
    }
    std.debug.print("{any}\n", .{rows});
}

test "dump-null-limit-test" {
    const allocator = std.testing.allocator;
    const bytes = [_]u8{ 0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9, 0xa, 0xb, 0xc, 0xd, 0xe, 0xf, 0x10, 0x11, 0x12 };
    const rows = try dump(allocator, bytes[0..], null, 4);
    defer {
        for (rows) |row| {
            allocator.free(row);
        }
        allocator.free(rows);
    }
    std.debug.print("{any}\n", .{rows});
}

test "dump-large-limit-test" {
    const allocator = std.testing.allocator;
    const bytes = [_]u8{ 0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9, 0xa, 0xb, 0xc, 0xd, 0xe, 0xf, 0x10, 0x11, 0x12 };
    const rows = try dump(allocator, bytes[0..], 99, 4);
    defer {
        for (rows) |row| {
            allocator.free(row);
        }
        allocator.free(rows);
    }
    std.debug.print("{any}\n", .{rows});
}

test "dump-small-limit-test" {
    const allocator = std.testing.allocator;
    const bytes = [_]u8{ 0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9, 0xa, 0xb, 0xc, 0xd, 0xe, 0xf, 0x10, 0x11, 0x12 };
    const rows = try dump(allocator, bytes[0..], 8, 4);
    defer {
        for (rows) |row| {
            allocator.free(row);
        }
        allocator.free(rows);
    }
    std.debug.print("{any}\n", .{rows});
}

test "dump-odd-group-test" {
    const allocator = std.testing.allocator;
    const bytes = [_]u8{ 0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9, 0xa, 0xb, 0xc, 0xd, 0xe, 0xf, 0x10, 0x11, 0x12 };
    const rows = try dump(allocator, bytes[0..], null, 3);
    defer {
        for (rows) |row| {
            allocator.free(row);
        }
        allocator.free(rows);
    }
    std.debug.print("{any}\n", .{rows});
}

test "dump-even-group-test" {
    const allocator = std.testing.allocator;
    const bytes = [_]u8{ 0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9, 0xa, 0xb, 0xc, 0xd, 0xe, 0xf, 0x10, 0x11, 0x12 };
    const rows = try dump(allocator, bytes[0..], null, 4);
    defer {
        for (rows) |row| {
            allocator.free(row);
        }
        allocator.free(rows);
    }
    std.debug.print("{any}\n", .{rows});
}

fn display_bytes(group_bytes: [][]u8) void {
    for (group_bytes) |group| {
        for (group) |byte| {
            std.debug.print("{x:0>2}", .{byte});
        }
        std.debug.print(" ", .{});
    }
}

fn display_bytes_little_endian(group_bytes: [][]u8) void {
    for (group_bytes) |group| {
        var idx = group.len;
        while (idx > 0) {
            idx -= 1;
            std.debug.print("{x:0>2}", .{group[idx]});
        }
        std.debug.print(" ", .{});
    }
}

fn display_as_text(bytes: []u8) void {
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
