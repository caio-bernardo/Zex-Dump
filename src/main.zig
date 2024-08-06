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
    // read_until: ?u32, //TODO: Implement this
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

    const chunck_size = args.num_cols;
    const chunks = contents.len / chunck_size + 1;

    for (1..chunks) |num| {
        const end = num * chunck_size;
        const start = end - chunck_size;

        display_offset(start, args.offset_decimal);

        if (args.little_endian) {
            display_as_little_endian(contents[start..end], args.group_size);
        } else {
            display_bytes(contents[start..end], args.group_size);
        }

        display_as_text(contents[start..end]);

        std.debug.print("\n", .{}); // TODO: remove debug prints for a stdout print
    }
}
/// Handle Cli Arguments
pub fn handle_args(allocator: std.mem.Allocator) ArgError!Args {
    var args = try std.process.argsWithAllocator(allocator);
    _ = args.skip(); // remove exe path

    var little_endian = false;
    var group_size: u8 = 0;
    var file_path: ?[:0]const u8 = undefined;
    // var read_until: ?u32 = null;
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
            // } else if (std.mem.eql(u8, arg, "-l")) {
            //     const buf = args.next() orelse return ArgError.NoValueAfter;
            //     read_until = std.fmt.parseUnsigned(u16, buf, 10) catch return ArgError.NotaNumber;
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
        // .read_until = read_until,
        .offset_decimal = offset_decimal,
        .num_cols = num_cols,
    };
}

fn dump(
    allocator: std.mem.Allocator,
    writer: anytype,
    contents: []const u8,
    limit: u8,
    group_max_size: usize,
) !void {
    var group = try std.ArrayList(u8).initCapacity(allocator, group_max_size);
    errdefer group.deinit();
    var rows = try std.ArrayList([]u8).initCapacity(allocator, 16);
    defer rows.deinit();
    for (contents, 1..) |byte, byte_reads| {
        group.append(byte) catch std.debug.print("Failed to append", .{});
        if (group.items.len == group_max_size or byte_reads == contents.len or byte_reads == limit) {
            const slice = try group.toOwnedSlice();
            try rows.append(slice);
        }

        if (byte_reads == limit) {
            break;
        }
    }

    for (rows.items) |slice| {
        // TODO: remove this by a formating function
        std.debug.print("{d}", .{slice});
        // need to free each slice
        allocator.free(slice);
    }

    _ = writer;
}

test "dump-limit" {
    const bytes = [16]u8{ 0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9, 0xa, 0xb, 0xc, 0xd, 0xe, 0xf };
    try dump(std.testing.allocator, std.io.getStdOut(), bytes[0..], 11, 2);
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
