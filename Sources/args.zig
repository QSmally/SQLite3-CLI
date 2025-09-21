
const std = @import("std");

pub const Binding = union(enum) {
    literal: []const u8,
    stdin
};

// https://github.com/QSmally/QCPU-CLI/blob/6ca9bf79931a5232a7eecfccf6b87f3b3b7305aa/Sources/qcpu.zig#L196
pub fn Arguments(comptime T: type) type {
    return struct {

        const ArgumentsType = @This();

        iterator: T,

        current_option: []const u8 = undefined,
        current_type: []const u8 = undefined,
        current_value: []const u8 = undefined,

        pub fn init(iterator: T) ArgumentsType {
            return .{ .iterator = iterator };
        }

        pub fn init_second(iterator: T) ArgumentsType {
            var arguments = ArgumentsType.init(iterator);
            _ = arguments.iterator.skip();
            return arguments;
        }

        pub fn next(self: *ArgumentsType) ?[]const u8 {
            const slice: []const u8 = @ptrCast(self.iterator.next() orelse return null);
            self.current_value = slice;
            return slice;
        }

        const Error = error { ArgumentExpected };

        pub fn expect(self: *ArgumentsType) Error![]const u8 {
            return self.next() orelse error.ArgumentExpected;
        }

        pub fn parse(self: *ArgumentsType, comptime OptionsType: type, allocator: std.mem.Allocator) !struct {
            []const []const u8,
            []const Binding,
            OptionsType
        } {
            var run_args: std.ArrayListUnmanaged([]const u8) = .empty;
            var run_bindings: std.ArrayListUnmanaged(Binding) = .empty;
            var run_options = OptionsType {};

            arg: while (self.next()) |argument| {
                if (std.mem.eql(u8, "--", argument))
                    break;
                inline for (@typeInfo(OptionsType).@"struct".fields) |option| {
                    const name = "--" ++ option.name;
                    const Type = option.@"type";

                    self.current_option = name;
                    self.current_type = @typeName(Type);

                    if (std.mem.eql(u8, name, argument)) {
                        const value = val: switch (Type) {
                            bool => true,

                            u16, u24, u32, u64 => {
                                const inherit = 0;
                                const input = try self.expect();
                                break :val try std.fmt.parseInt(Type, input, inherit);
                            },

                            []const u8,
                            ?[]const u8 => try self.expect(),

                            else => @compileError("bug: unsupported option type: " ++ @typeName(Type))
                        };

                        @field(run_options, option.name) = value;
                        continue :arg;
                    }
                }

                if (std.mem.eql(u8, argument, "--bind")) {
                    try run_bindings.append(allocator, .{ .literal = try self.expect() });
                    continue;
                }

                if (std.mem.eql(u8, argument, "--bind-stdin")) {
                    try run_bindings.append(allocator, .stdin);
                    continue;
                }

                if (std.mem.startsWith(u8, argument, "--"))
                    return error.OptionNotFound;
                try run_args.append(allocator, argument);
            }

            return .{
                try run_args.toOwnedSlice(allocator),
                try run_bindings.toOwnedSlice(allocator),
                run_options };
        }
    };
}

// Tests

test "arguments iterator" {
    const foo = std.mem.splitScalar(u8, "foo bar roo", ' ');
    var iterator = Arguments(@TypeOf(foo)).init(foo);

    try std.testing.expectEqualSlices(u8, "foo", iterator.next() orelse "x");
    try std.testing.expectEqualSlices(u8, "bar", iterator.next() orelse "x");
    try std.testing.expectEqualSlices(u8, "roo", iterator.next() orelse "x");
    try std.testing.expectEqual(@as(?[]const u8, null), iterator.next());
}

const TestOptions = struct {
    foo: bool = false,
    bar: bool = false,
    roo: ?[]const u8 = null,
    doo: bool = false,
    loo: u16 = 0
};

test "arguments parser simple correctly" {
    const foo = std.mem.splitScalar(u8, "--foo --bar aaa", ' ');
    var iterator = Arguments(@TypeOf(foo)).init(foo);
    const positional, _, const tagged = try iterator.parse(TestOptions, std.testing.allocator);
    defer std.testing.allocator.free(positional);

    try std.testing.expectEqual(true, tagged.foo);
    try std.testing.expectEqual(true, tagged.bar);
    try std.testing.expectEqual(@as(?[]const u8, null), tagged.roo);
    try std.testing.expectEqual(false, tagged.doo);
    try std.testing.expectEqual(@as(u16, 0), tagged.loo);

    try std.testing.expect(positional.len == 1);
    try std.testing.expectEqualSlices(u8, "aaa", positional[0]);
}

test "arguments parser advanced correctly" {
    const foo = std.mem.splitScalar(u8, "--roo bbb --loo 5 aaa", ' ');
    var iterator = Arguments(@TypeOf(foo)).init(foo);
    const positional, _, const tagged = try iterator.parse(TestOptions, std.testing.allocator);
    defer std.testing.allocator.free(positional);

    try std.testing.expectEqual(false, tagged.foo);
    try std.testing.expectEqual(false, tagged.bar);
    try std.testing.expectEqualSlices(u8, "bbb", tagged.roo.?);
    try std.testing.expectEqual(false, tagged.doo);
    try std.testing.expectEqual(@as(u16, 5), tagged.loo);

    try std.testing.expect(positional.len == 1);
    try std.testing.expectEqualSlices(u8, "aaa", positional[0]);
}

test "arguments parser list correctly" {
    const foo = std.mem.splitScalar(u8, "foo bar --foo --bind roo --bind-stdin", ' ');
    var iterator = Arguments(@TypeOf(foo)).init(foo);
    const positional, const binding, const tagged = try iterator.parse(TestOptions, std.testing.allocator);
    defer std.testing.allocator.free(positional);
    defer std.testing.allocator.free(binding);

    try std.testing.expectEqual(true, tagged.foo);
    try std.testing.expectEqual(false, tagged.bar);

    try std.testing.expect(positional.len == 2);
    try std.testing.expectEqualSlices(u8, "foo", positional[0]);
    try std.testing.expectEqualSlices(u8, "bar", positional[1]);

    try std.testing.expect(binding.len == 2);
    try std.testing.expect(binding[0] == .literal);
    try std.testing.expectEqualSlices(u8, "roo", binding[0].literal);
    try std.testing.expect(binding[1] == .stdin);
}

test "arguments parser advanced incorrectly 1" {
    const foo = std.mem.splitScalar(u8, "--roo", ' ');
    var iterator = Arguments(@TypeOf(foo)).init(foo);
    const err = iterator.parse(TestOptions, std.testing.allocator);

    try std.testing.expectError(error.ArgumentExpected, err);
}

test "arguments parser advanced incorrectly 2" {
    const foo = std.mem.splitScalar(u8, "--loo 0xFFFFFF", ' ');
    var iterator = Arguments(@TypeOf(foo)).init(foo);
    const err = iterator.parse(TestOptions, std.testing.allocator);

    try std.testing.expectError(error.Overflow, err);
}

test "arguments parser advanced incorrectly 3" {
    const foo = std.mem.splitScalar(u8, "--aaa 0xFFFFFF", ' ');
    var iterator = Arguments(@TypeOf(foo)).init(foo);
    const err = iterator.parse(TestOptions, std.testing.allocator);

    try std.testing.expectError(error.OptionNotFound, err);
}
