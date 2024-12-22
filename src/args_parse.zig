const std = @import("std");

pub const ArgError = error{ NotaNumber, NoValueAfter, NoFilePath, NotOctet, InitError, HelpString, VersionString, AllocationFailed };

pub const Args = struct {
    file_path: [:0]const u8 = undefined,
    group_size: u8 = 2,
    little_endian: bool = false,
    offset: usize = 0,
    offset_decimal: bool = false,
    read_limit: ?usize = null,
    revert: bool = false,
    row_len: u8 = 16,
    seek: usize = 0,
    upperhex: bool = false,

    /// Read and parse args, caller owns the data
    pub fn init(allocator: std.mem.Allocator) ArgError!Args {
        var args: std.process.ArgIterator = std.process.argsWithAllocator(allocator) catch return ArgError.AllocationFailed;
        defer args.deinit();

        _ = args.skip(); // remove exe path

        var arg_parsed: Args = Args{};
        var file_path: ?[:0]const u8 = null;

        while (args.next()) |arg| {
            if (std.mem.eql(u8, arg, "-c")) {
                const buf = args.next() orelse return ArgError.NoValueAfter;
                arg_parsed.row_len = std.fmt.parseUnsigned(u8, buf, 10) catch return ArgError.NotaNumber;
            } else if (std.mem.eql(u8, arg, "-d")) {
                arg_parsed.offset_decimal = true;
            } else if (std.mem.eql(u8, arg, "-e")) {
                arg_parsed.little_endian = true;
                if (arg_parsed.group_size == 0) {
                    arg_parsed.group_size = 4;
                    // Check if group_size is a power of 2
                } else if (arg_parsed.group_size <= 16 and (arg_parsed.group_size & (arg_parsed.group_size - 1)) == 0) {
                    return ArgError.NotOctet;
                }
            } else if (std.mem.eql(u8, arg, "-g")) {
                const buf = args.next() orelse return ArgError.NoValueAfter;
                arg_parsed.group_size = std.fmt.parseUnsigned(u8, buf, 10) catch return ArgError.NotaNumber;
            } else if (std.mem.eql(u8, arg, "-h")) {
                return ArgError.HelpString;
            } else if (std.mem.eql(u8, arg, "-l")) {
                const buf = args.next() orelse return ArgError.NoValueAfter;
                arg_parsed.read_limit = std.fmt.parseUnsigned(usize, buf, 10) catch return ArgError.NotaNumber;
            } else if (std.mem.eql(u8, arg, "-o")) {
                const buf = args.next() orelse return ArgError.NoValueAfter;
                arg_parsed.offset = std.fmt.parseUnsigned(usize, buf, 10) catch return ArgError.NotaNumber;
            } else if (std.mem.eql(u8, arg, "-r")) {
                arg_parsed.revert = true;
            } else if (std.mem.eql(u8, arg, "-s")) {
                const buf = args.next() orelse return ArgError.NoValueAfter;
                arg_parsed.seek = std.fmt.parseUnsigned(usize, buf, 10) catch return ArgError.NotaNumber;
            } else if (std.mem.eql(u8, arg, "-u")) {
                arg_parsed.upperhex = true;
            } else if (std.mem.eql(u8, arg, "-v")) {
                return ArgError.VersionString;
            } else {
                file_path = arg;
            }
        }

        arg_parsed.file_path = file_path orelse return ArgError.NoFilePath;
        if (arg_parsed.group_size == 0) arg_parsed.group_size = 2;

        return arg_parsed;
    }
};
