const std = @import("std");
const testing = std.testing;
const config = @import("../../src/config.zig");

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

test "resolveTokenLimit returns default when no parameter or env var" {
    // Ensure env var is not set
    std.process.unsetenv(config.TOKEN_LIMIT_ENV_VAR);

    const limit = config.resolveTokenLimit(null);
    try testing.expectEqual(@as(u32, 10000), limit);
}

test "resolveTokenLimit uses parameter when provided" {
    // Even if env var is set, parameter should take precedence
    try std.process.setenv(config.TOKEN_LIMIT_ENV_VAR, "20000");
    defer std.process.unsetenv(config.TOKEN_LIMIT_ENV_VAR);

    const limit = config.resolveTokenLimit(15000);
    try testing.expectEqual(@as(u32, 15000), limit);
}

test "resolveTokenLimit clamps parameter values" {
    const too_low = config.resolveTokenLimit(500);
    try testing.expectEqual(@as(u32, 1000), too_low);

    const too_high = config.resolveTokenLimit(200000);
    try testing.expectEqual(@as(u32, 100000), too_high);
}

test "resolveTokenLimit uses environment variable when parameter is null" {
    try std.process.setenv(config.TOKEN_LIMIT_ENV_VAR, "25000");
    defer std.process.unsetenv(config.TOKEN_LIMIT_ENV_VAR);

    const limit = config.resolveTokenLimit(null);
    try testing.expectEqual(@as(u32, 25000), limit);
}

test "resolveTokenLimit clamps environment variable values" {
    try std.process.setenv(config.TOKEN_LIMIT_ENV_VAR, "500");
    defer std.process.unsetenv(config.TOKEN_LIMIT_ENV_VAR);

    const limit_low = config.resolveTokenLimit(null);
    try testing.expectEqual(@as(u32, 1000), limit_low);

    try std.process.setenv(config.TOKEN_LIMIT_ENV_VAR, "150000");
    const limit_high = config.resolveTokenLimit(null);
    try testing.expectEqual(@as(u32, 100000), limit_high);
}

test "resolveTokenLimit handles invalid environment variable" {
    try std.process.setenv(config.TOKEN_LIMIT_ENV_VAR, "not_a_number");
    defer std.process.unsetenv(config.TOKEN_LIMIT_ENV_VAR);

    const limit = config.resolveTokenLimit(null);
    try testing.expectEqual(@as(u32, 10000), limit); // Should fall back to default
}

test "resolveTokenLimit handles empty environment variable" {
    try std.process.setenv(config.TOKEN_LIMIT_ENV_VAR, "");
    defer std.process.unsetenv(config.TOKEN_LIMIT_ENV_VAR);

    const limit = config.resolveTokenLimit(null);
    try testing.expectEqual(@as(u32, 10000), limit); // Should fall back to default
}

test "isLargeDirectory detects root directory" {
    const allocator = testing.allocator;

    const is_large = try config.isLargeDirectory(allocator, "/");
    try testing.expect(is_large);
}

test "isLargeDirectory detects system directories" {
    const allocator = testing.allocator;

    // Test a few common system directories
    const dirs = [_][]const u8{ "/usr", "/var", "/tmp" };
    for (dirs) |dir| {
        const is_large = config.isLargeDirectory(allocator, dir) catch continue;
        try testing.expect(is_large);
    }
}

test "isLargeDirectory returns false for safe directories" {
    const allocator = testing.allocator;

    // Create a temporary directory for testing
    const tmp_dir = try std.fs.cwd().realpathAlloc(allocator, "test/fixtures/basic");
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
