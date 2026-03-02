const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const config = @import("stump").config;

test "clampTokenLimit clamps values below minimum" {
    try testing.expectEqual(@as(u32, 1000), config.clampTokenLimit(0));
    try testing.expectEqual(@as(u32, 1000), config.clampTokenLimit(500));
    try testing.expectEqual(@as(u32, 1000), config.clampTokenLimit(999));
}

test "clampTokenLimit preserves values within range" {
    try testing.expectEqual(@as(u32, 1000), config.clampTokenLimit(1000));
    try testing.expectEqual(@as(u32, 5000), config.clampTokenLimit(5000));
    try testing.expectEqual(@as(u32, 10000), config.clampTokenLimit(10000));
    try testing.expectEqual(@as(u32, 50000), config.clampTokenLimit(50000));
    try testing.expectEqual(@as(u32, 100000), config.clampTokenLimit(100000));
}

test "clampTokenLimit clamps values above maximum" {
    try testing.expectEqual(@as(u32, 100000), config.clampTokenLimit(100001));
    try testing.expectEqual(@as(u32, 100000), config.clampTokenLimit(200000));
    try testing.expectEqual(@as(u32, 100000), config.clampTokenLimit(1000000));
}

test "resolveTokenLimit uses parameter when provided" {
    // Parameter should take precedence over any env var
    const limit = config.resolveTokenLimit(15000);
    try testing.expectEqual(@as(u32, 15000), limit);
}

test "resolveTokenLimit clamps parameter values" {
    const too_low = config.resolveTokenLimit(500);
    try testing.expectEqual(@as(u32, 1000), too_low);

    const too_high = config.resolveTokenLimit(200000);
    try testing.expectEqual(@as(u32, 100000), too_high);
}

test "resolveTokenLimit returns value in valid range when no parameter" {
    // When no parameter is provided, result should still be in valid range
    // (either from env var or default)
    const limit = config.resolveTokenLimit(null);
    try testing.expect(limit >= config.MIN_TOKEN_LIMIT);
    try testing.expect(limit <= config.MAX_TOKEN_LIMIT);
}

test "isLargeDirectory detects root directory" {
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest;
    const allocator = testing.allocator;

    const is_large = try config.isLargeDirectory(allocator, "/");
    try testing.expect(is_large);
}

test "isLargeDirectory detects system directories" {
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest;
    const allocator = testing.allocator;

    // Test /usr which should exist on most Unix systems
    const is_usr_large = config.isLargeDirectory(allocator, "/usr") catch |err| {
        // If /usr doesn't exist or can't be accessed, skip test
        if (err == error.FileNotFound or err == error.AccessDenied) {
            return;
        }
        return err;
    };
    try testing.expect(is_usr_large);
}

test "isLargeDirectory returns false for safe directories" {
    const allocator = testing.allocator;

    // Create a temporary directory for testing
    const tmp_dir = std.fs.cwd().realpathAlloc(allocator, "test/fixtures/basic") catch return;
    defer allocator.free(tmp_dir);

    const is_large = try config.isLargeDirectory(allocator, tmp_dir);
    try testing.expect(!is_large);
}

test "isLargeDirectory handles relative paths" {
    const allocator = testing.allocator;

    // Test with relative path to a safe directory
    const is_large = config.isLargeDirectory(allocator, "test/fixtures/basic") catch |err| {
        // If the path doesn't exist in test context, that's okay
        if (err == error.FileNotFound) {
            return;
        }
        return err;
    };
    try testing.expect(!is_large);
}

test "Constants have expected values" {
    try testing.expectEqual(@as(u32, 1000), config.MIN_TOKEN_LIMIT);
    try testing.expectEqual(@as(u32, 100000), config.MAX_TOKEN_LIMIT);
    try testing.expectEqual(@as(u32, 10000), config.DEFAULT_TOKEN_LIMIT);
    try testing.expectEqualStrings("STUMP_TOKEN_LIMIT", config.TOKEN_LIMIT_ENV_VAR);
}

test "LARGE_DIRECTORIES contains expected paths" {
    if (comptime builtin.os.tag == .windows) {
        const win_expected = [_][]const u8{
            "C:\\", "C:\\Windows", "C:\\Users", "C:\\Program Files",
        };
        for (win_expected) |expected_dir| {
            var found = false;
            for (config.LARGE_DIRECTORIES) |dir| {
                if (std.mem.eql(u8, dir, expected_dir)) {
                    found = true;
                    break;
                }
            }
            try testing.expect(found);
        }
        return;
    }
    const expected = [_][]const u8{
        "/", "/usr", "/var", "/home", "/System",
        "/Library", "/Applications", "/etc", "/opt",
    };

    for (expected) |expected_dir| {
        var found = false;
        for (config.LARGE_DIRECTORIES) |dir| {
            if (std.mem.eql(u8, dir, expected_dir)) {
                found = true;
                break;
            }
        }
        try testing.expect(found);
    }
}

test "tokenLimitToBytes converts correctly" {
    try testing.expectEqual(@as(u32, 4000), config.tokenLimitToBytes(1000));
    try testing.expectEqual(@as(u32, 40000), config.tokenLimitToBytes(10000));
    try testing.expectEqual(@as(u32, 400000), config.tokenLimitToBytes(100000));
}
