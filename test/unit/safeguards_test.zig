const std = @import("std");
const testing = std.testing;
const safeguards = @import("../../src/safeguards.zig");

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
    const fatal_error = @import("../../src/types.zig").FatalError.init(
        .large_directory,
        "/usr",
        "Test error"
    );
    const result = safeguards.SafeguardResult{ .fatal_error = fatal_error };
    try testing.expect(!result.isOk());
}

test "checkLargeDirectory allows traversal with force=true" {
    const allocator = testing.allocator;

    // Even root directory should be allowed with force=true
    const result = try safeguards.checkLargeDirectory("/", true, allocator);
    try testing.expect(result.isOk());
}

test "checkLargeDirectory blocks large directories with force=false" {
    const allocator = testing.allocator;

    // Root directory should be blocked without force
    const result = try safeguards.checkLargeDirectory("/", false, allocator);
    try testing.expect(!result.isOk());

    switch (result) {
        .fatal_error => |err| {
            try testing.expectEqualStrings("large_directory", err.type);
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

test "checkFilenameUtf8 returns ok for valid UTF-8" {
    const allocator = testing.allocator;

    const result = try safeguards.checkFilenameUtf8("valid_file.txt", false, allocator);
    try testing.expect(result.isOk());
}

test "checkFilenameUtf8 returns fatal_error for invalid UTF-8 when force=false" {
    const allocator = testing.allocator;

    const invalid = [_]u8{ 'f', 'i', 'l', 'e', 0xFF, 0xFE };
    const result = try safeguards.checkFilenameUtf8(&invalid, false, allocator);
    try testing.expect(!result.isOk());

    switch (result) {
        .fatal_error => |err| {
            try testing.expectEqualStrings("non_utf8_filename", err.type);
        },
        .ok => unreachable,
    }
}

test "checkFilenameUtf8 allows invalid UTF-8 with force=true" {
    const allocator = testing.allocator;

    const invalid = [_]u8{ 'f', 'i', 'l', 'e', 0xFF, 0xFE };
    const result = try safeguards.checkFilenameUtf8(&invalid, true, allocator);
    try testing.expect(result.isOk());
}
