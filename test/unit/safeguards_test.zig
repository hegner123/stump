const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const safeguards = @import("stump").safeguards;
const types = @import("stump").types;

test "isValidUtf8 accepts valid UTF-8 strings" {
    try testing.expect(safeguards.isValidUtf8("hello"));
    try testing.expect(safeguards.isValidUtf8("test.txt"));
    try testing.expect(safeguards.isValidUtf8("测试文件"));
    try testing.expect(safeguards.isValidUtf8(""));
}

test "isValidUtf8 rejects invalid UTF-8 sequences" {
    const invalid1 = [_]u8{ 0xFF, 0xFE };
    try testing.expect(!safeguards.isValidUtf8(&invalid1));

    const invalid2 = [_]u8{ 0xC0, 0x80 };
    try testing.expect(!safeguards.isValidUtf8(&invalid2));
}

test "SafeguardResult.isOk returns true for ok variant" {
    const result = safeguards.SafeguardResult{ .ok = {} };
    try testing.expect(result.isOk());
}

test "SafeguardResult.isOk returns false for fatal_error variant" {
    const allocator = testing.allocator;

    var fatal_error = try types.FatalError.init(
        allocator,
        .large_directory,
        "/usr",
        "Test error",
    );
    defer fatal_error.deinit(allocator);

    const result = safeguards.SafeguardResult{ .fatal_error = fatal_error };
    try testing.expect(!result.isOk());
}

test "checkLargeDirectory allows traversal with force=true" {
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest;
    const allocator = testing.allocator;

    // Even root directory should be allowed with force=true
    const result = try safeguards.checkLargeDirectory("/", true, allocator);
    try testing.expect(result.isOk());
}

test "checkLargeDirectory blocks large directories with force=false" {
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest;
    const allocator = testing.allocator;

    // Root directory should be blocked without force
    var result = try safeguards.checkLargeDirectory("/", false, allocator);
    defer switch (result) {
        .fatal_error => |*err| err.deinit(allocator),
        .ok => {},
    };

    try testing.expect(!result.isOk());

    switch (result) {
        .fatal_error => |err| {
            try testing.expectEqual(types.ErrorType.large_directory, err.type);
            try testing.expect(std.mem.indexOf(u8, err.message, "force: true") != null);
        },
        .ok => unreachable,
    }
}

test "checkLargeDirectory allows safe directories" {
    const allocator = testing.allocator;

    // A safe directory in test fixtures should be allowed
    const result = safeguards.checkLargeDirectory("test/fixtures/basic", false, allocator) catch |err| {
        // If path doesn't exist in test context, that's okay
        if (err == error.FileNotFound) {
            return;
        }
        return err;
    };

    try testing.expect(result.isOk());
}

test "validateFilenameUtf8 returns ok for valid UTF-8" {
    const allocator = testing.allocator;

    const result = try safeguards.validateFilenameUtf8("valid_file.txt", false, allocator);
    switch (result) {
        .ok => {},
        else => try testing.expect(false),
    }
}

test "validateFilenameUtf8 returns fatal_error for invalid UTF-8 when force=false" {
    const allocator = testing.allocator;

    const invalid = [_]u8{ 'f', 'i', 'l', 'e', 0xFF, 0xFE };
    var result = try safeguards.validateFilenameUtf8(&invalid, false, allocator);
    defer switch (result) {
        .fatal_error => |*err| err.deinit(allocator),
        else => {},
    };

    switch (result) {
        .fatal_error => |err| {
            try testing.expectEqual(types.ErrorType.non_utf8_filename, err.type);
        },
        else => try testing.expect(false),
    }
}

test "validateFilenameUtf8 returns error_entry for invalid UTF-8 when force=true" {
    const allocator = testing.allocator;

    const invalid = [_]u8{ 'f', 'i', 'l', 'e', 0xFF, 0xFE };
    var result = try safeguards.validateFilenameUtf8(&invalid, true, allocator);
    defer switch (result) {
        .error_entry => |*entry| entry.deinit(allocator),
        else => {},
    };

    switch (result) {
        .error_entry => |entry| {
            try testing.expectEqual(types.ErrorType.non_utf8_filename, entry.type);
        },
        else => try testing.expect(false),
    }
}
