const std = @import("std");

// Max bytes to read from a file =
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
    read_limit: ?u32,
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
    const groups = try dump(allocator, contents, args.read_limit, args.group_size);
    defer {
        for (groups) |group| {
            allocator.free(group);
        }
        allocator.free(groups);
    }

    const groups_per_row = args.num_cols / args.group_size;
    const rows = groups.len / groups_per_row + 1;
    for (1..rows) |row_num| {
        const end = row_num * groups_per_row;
        const start = end - groups_per_row;
        display_offset(start, args.offset_decimal);

        for (groups[start..end]) |byte| {
            std.debug.print("{x:0>2}", .{byte});
        }
        std.debug.print(" ", .{});

        std.debug.print("\n", .{});
    }
}
/// Handle Cli Arguments
pub fn handle_args(allocator: std.mem.Allocator) ArgError!Args {
    var args = try std.process.argsWithAllocator(allocator);
    _ = args.skip(); // remove exe path

    var little_endian = false;
    var group_size: u8 = 0;
    var file_path: ?[:0]const u8 = undefined;
    var read_limit: ?u32 = null;
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
            read_limit = std.fmt.parseUnsigned(u16, buf, 10) catch return ArgError.NotaNumber;
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
    read_limit: ?u32,
    group_max_size: usize,
) ![][]u8 {
    const limit = read_limit orelse 0;

    var group = try std.ArrayList(u8).initCapacity(allocator, group_max_size);
    errdefer group.deinit();

    var rows = std.ArrayList([]u8).init(allocator);
    errdefer rows.deinit();

    for (contents, 1..) |byte, byte_reads| {
        try group.append(byte);
        if (group.items.len == group_max_size or byte_reads == contents.len or limit == byte_reads) {
            try rows.append(try group.toOwnedSlice());
        }
        if (byte_reads == limit) {
            break;
        }
    }

    return rows.toOwnedSlice();
}

test "dump-test" {
    const allocator = std.testing.allocator;
    const bytes = [16]u8{ 0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9, 0xa, 0xb, 0xc, 0xd, 0xe, 0xf };
    const rows = try dump(allocator, bytes[0..], 16, 2);
    defer {
        for (rows) |row| {
            allocator.free(row);
        }
        allocator.free(rows);
    }
    std.debug.print("{any}", .{rows});
}

fn display_bytes(bytes: []u8, group_size: u8) void {
    for (bytes, 1..) |byte, idx| {
        std.debug.print("{x:0>2}", .{byte});
        const sep = if (idx % group_size == 0) " " else "";
        std.debug.print("{s}", .{sep});
    }
}

fn display_as_little_endian(bytes: []u8, group_size: u8) void {
    if (group_size > 16 or group_size & (group_size - 1) != 0) unreachable; // TODO: treat this error

    var start: u8 = 0;
    var end = group_size;
    const groups = bytes.len / group_size;
    for (0..groups) |_| {
        const slice = bytes[start..end];
        var i = slice.len;
        while (i > 0) {
            i -= 1;
            std.debug.print("{x:0>2}", .{slice[i]});
        }
        std.debug.print(" ", .{});
        start = end;
        end += group_size;
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
