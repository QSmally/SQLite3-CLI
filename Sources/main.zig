
const std = @import("std");
const args = @import("args.zig");
const sqlite3 = @import("sqlite3");

// https://github.com/QSmally/QCPU-CLI/blob/6ca9bf79931a5232a7eecfccf6b87f3b3b7305aa/Sources/qcpu.zig#L21
fn help(raw_writer: anytype) !void {
    var buffer = std.io.bufferedWriter(raw_writer);
    defer buffer.flush() catch {};
    var writer = buffer.writer();

    try writer.writeAll(
        \\
        \\    SQLite3 CLI
        \\    sqlite3-cli [option ...] file query
        \\
        \\parameter bindings
        \\    --bind string
        \\    --bind-stdin
        \\
        \\
    );

    inline for (&[_]struct { []const u8, type } {
        .{ "options", Options }
    }) |category| {
        try writer.print("{s}\n", .{ category[0] });

        inline for (@typeInfo(category[1]).@"struct".fields) |field| {
            const fancy_type = switch (field.@"type") {
                []const u8 => "string (default " ++ field.defaultValue().? ++ ")",
                ?[]const u8 => "string (default none)",
                bool => "",
                u3, u16, u32, u64 => @typeName(field.@"type") ++ " (default " ++ std.fmt.comptimePrint("{}", .{ field.defaultValue().? }) ++ ")",
                ?u3, ?u16, ?u32, ?u64 => @typeName(field.@"type") ++ " (default none)",
                else => @typeName(field.@"type")
            };

            try writer.print("    --{s} {s}\n", .{ field.name, fancy_type });
        }

        try writer.writeAll("\n");
    }
}

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();
    var arguments = args.Arguments(std.process.ArgIterator).init_second(std.process.args());

    const run_args,
    const run_bindings,
    const run_options = arguments.parse(Options, allocator) catch |err| {
        switch (err) {
            // error.InvalidCharacter => std.log.err("{s}: invalid numeric '{s}'", .{ arguments.current_option, arguments.current_value }),
            // error.Overflow => std.log.err("{s}: {s} doesn't fit in type {s}", .{ arguments.current_option, arguments.current_value, arguments.current_type }),
            error.ArgumentExpected => std.log.err("{s}: expected option value", .{ arguments.current_option }),
            error.OptionNotFound => std.log.err("{s}: unknown option", .{  arguments.current_value }),
            error.OutOfMemory => std.log.err("out of memory", .{})
        }
        return 1;
    };

    if (run_options.doptions)
        std.debug.print("{any} {any} {any}\n", .{ run_args, run_bindings, run_options });

    if (run_options.help) {
        try help(stdout);
        return 0;
    }

    if (run_args.len != 2) {
        std.log.err("expected exactly 2 arguments: file, query", .{});
        return 1;
    }

    var db = try sqlite3.Db.init(.{
        .mode = .{ .File = try allocator.dupeZ(u8, run_args[0]) },
        .open_flags = .{
            .write = !run_options.readonly,
            .create = !run_options.nocreate },
        .threading_mode = .MultiThread });
    defer db.deinit();

    const bindings = try bind(allocator, run_bindings, run_options);
    try prepare(&db, run_options);
    try execute(&db, run_args[1], bindings);

    return 0;
}

const Options = struct {
    readonly: bool = false,
    nocreate: bool = false,
    nodefaults: bool = false,
    notrim: bool = false,
    doptions: bool = false,
    help: bool = false
};

var gpa = std.heap.GeneralPurposeAllocator(.{}) {};

const stdin = std.io
    .getStdIn()
    .reader();
const stdout = std.io
    .getStdOut()
    .writer();

fn prepare(db: *sqlite3.Db, options: Options) !void {
    if (!options.nodefaults) {
        _ = try db.pragma(void, .{}, "busy_timeout", "1000");
    }
}

const max_size = 4096 * 16;

fn bind(
    arena: std.mem.Allocator,
    bindings: []const args.Binding,
    options: Options
) ![]const []const u8 {
    var values: std.ArrayListUnmanaged([]const u8) = .empty;
    var input: ?[]const u8 = null;

    for (bindings) |binding| switch (binding) {
        .literal => |literal| try values.append(arena, literal),
        .stdin => {
            if (input) |the_input| {
                try values.append(arena, the_input);
            } else {
                input = try stdin.readAllAlloc(arena, max_size);
                if (!options.notrim) input = std.mem.trim(u8, input.?, &std.ascii.whitespace);
                try values.append(arena, input.?);
            }
        }
    };
    
    return values.items;
}

fn execute(
    db: *sqlite3.Db,
    query: []const u8,
    bindings: []const []const u8
) !void {
    var diagnostics = sqlite3.Diagnostics {};

    var statement = db.prepareDynamicWithDiags(query, .{ .diags = &diagnostics }) catch |err| {
        std.log.err("{}: {s}", .{ err, diagnostics });
        return err;
    };
    defer statement.deinit();

    try statement.exec(.{ .diags = &diagnostics }, bindings);
}
