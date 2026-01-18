const std = @import("std");

/// Token limit constants
pub const MIN_TOKEN_LIMIT: u32 = 1000;
pub const MAX_TOKEN_LIMIT: u32 = 100000;
pub const DEFAULT_TOKEN_LIMIT: u32 = 10000;

/// Environment variable name for token limit
pub const TOKEN_LIMIT_ENV_VAR = "STUMP_TOKEN_LIMIT";

/// Large directory paths that should trigger warnings
/// These directories typically contain thousands or millions of files
pub const LARGE_DIRECTORIES = [_][]const u8{
    // Root and system directories
    "/",
    "/usr",
    "/var",
    "/home",
    "/System",
    "/Library",
    "/Applications",

    // Common Linux system directories
    "/etc",
    "/opt",
    "/srv",
    "/tmp",
    "/boot",
    "/dev",
    "/proc",
    "/sys",
    "/run",

    // Common macOS directories
    "/Users",
    "/Volumes",
    "/private",
    "/cores",
};

/// Resolves the token limit from multiple sources with priority:
/// 1. Explicit parameter (highest priority)
/// 2. Environment variable (STUMP_TOKEN_LIMIT)
/// 3. Default value (10,000 tokens)
/// Returns clamped value within valid range [1k-100k]
pub fn resolveTokenLimit(param_limit: ?u32) u32 {
    // Priority 1: Explicit parameter
    if (param_limit) |limit| {
        return clampTokenLimit(limit);
    }

    // Priority 2: Environment variable
    if (std.process.getEnvVarOwned(
        std.heap.page_allocator,
        TOKEN_LIMIT_ENV_VAR,
    )) |env_value| {
        defer std.heap.page_allocator.free(env_value);

        if (std.fmt.parseInt(u32, env_value, 10)) |limit| {
            return clampTokenLimit(limit);
        } else |_| {
            // Invalid env var value, fall through to default
        }
    } else |_| {
        // Env var not set, fall through to default
    }

    // Priority 3: Default
    return DEFAULT_TOKEN_LIMIT;
}

/// Clamps token limit to valid range [MIN_TOKEN_LIMIT, MAX_TOKEN_LIMIT]
pub fn clampTokenLimit(limit: u32) u32 {
    if (limit < MIN_TOKEN_LIMIT) {
        return MIN_TOKEN_LIMIT;
    }
    if (limit > MAX_TOKEN_LIMIT) {
        return MAX_TOKEN_LIMIT;
    }
    return limit;
}

/// Checks if a given path matches a known large directory
/// Performs canonical path comparison to handle symlinks and relative paths
/// Returns true if path is a large directory that should trigger warnings
pub fn isLargeDirectory(allocator: std.mem.Allocator, path: []const u8) !bool {
    // Resolve to canonical absolute path
    const canonical_path = try std.fs.realpathAlloc(allocator, path);
    defer allocator.free(canonical_path);

    // Check against known large directories
    for (LARGE_DIRECTORIES) |large_dir| {
        if (std.mem.eql(u8, canonical_path, large_dir)) {
            return true;
        }
    }

    // Check if path is a user home directory (e.g., /home/username or /Users/username)
    // This catches individual user home roots which can be massive
    if (isUserHomeDirectory(canonical_path)) {
        return true;
    }

    return false;
}

/// Checks if path appears to be a user home directory root
/// Examples: /home/user, /Users/user, /root
fn isUserHomeDirectory(path: []const u8) bool {
    // Check for /home/* pattern (Linux)
    if (std.mem.startsWith(u8, path, "/home/")) {
        const after_home = path[6..];
        // If there's a username but no further path, it's a home root
        const slash_pos = std.mem.indexOf(u8, after_home, "/");
        return slash_pos == null and after_home.len > 0;
    }

    // Check for /Users/* pattern (macOS)
    if (std.mem.startsWith(u8, path, "/Users/")) {
        const after_users = path[7..];
        const slash_pos = std.mem.indexOf(u8, after_users, "/");
        return slash_pos == null and after_users.len > 0;
    }

    // Check for /root (Linux root user home)
    if (std.mem.eql(u8, path, "/root")) {
        return true;
    }

    return false;
}

/// Converts token limit to byte limit using 4 chars/token approximation
pub fn tokenLimitToBytes(token_limit: u32) u32 {
    return token_limit * 4;
}

test "resolveTokenLimit with parameter" {
    const limit = resolveTokenLimit(5000);
    try std.testing.expectEqual(@as(u32, 5000), limit);
}

test "resolveTokenLimit with out-of-range parameter" {
    // Below minimum
    const low = resolveTokenLimit(500);
    try std.testing.expectEqual(MIN_TOKEN_LIMIT, low);

    // Above maximum
    const high = resolveTokenLimit(200000);
    try std.testing.expectEqual(MAX_TOKEN_LIMIT, high);
}

test "resolveTokenLimit default when no parameter" {
    const limit = resolveTokenLimit(null);
    // Will be either env var value or default
    // Since we can't control env in tests reliably, just check it's in range
    try std.testing.expect(limit >= MIN_TOKEN_LIMIT);
    try std.testing.expect(limit <= MAX_TOKEN_LIMIT);
}

test "clampTokenLimit" {
    try std.testing.expectEqual(@as(u32, 5000), clampTokenLimit(5000));
    try std.testing.expectEqual(MIN_TOKEN_LIMIT, clampTokenLimit(0));
    try std.testing.expectEqual(MIN_TOKEN_LIMIT, clampTokenLimit(500));
    try std.testing.expectEqual(MAX_TOKEN_LIMIT, clampTokenLimit(200000));
    try std.testing.expectEqual(MAX_TOKEN_LIMIT, clampTokenLimit(150000));
}

test "tokenLimitToBytes" {
    try std.testing.expectEqual(@as(u32, 40000), tokenLimitToBytes(10000));
    try std.testing.expectEqual(@as(u32, 4000), tokenLimitToBytes(1000));
    try std.testing.expectEqual(@as(u32, 400000), tokenLimitToBytes(100000));
}

test "isUserHomeDirectory" {
    try std.testing.expect(isUserHomeDirectory("/home/alice"));
    try std.testing.expect(isUserHomeDirectory("/Users/bob"));
    try std.testing.expect(isUserHomeDirectory("/root"));

    try std.testing.expect(!isUserHomeDirectory("/home/alice/Documents"));
    try std.testing.expect(!isUserHomeDirectory("/Users/bob/projects"));
    try std.testing.expect(!isUserHomeDirectory("/home"));
    try std.testing.expect(!isUserHomeDirectory("/Users"));
    try std.testing.expect(!isUserHomeDirectory("/"));
}
