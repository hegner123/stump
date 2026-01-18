const std = @import("std");
const types = @import("types.zig");
const errors = @import("errors.zig");

/// Large directory paths that should trigger warnings
/// These directories typically contain thousands or millions of files
const LARGE_DIRECTORIES = [_][]const u8{
    // Unix/Linux/macOS system directories
    "/",
    "/usr",
    "/var",
    "/home",
    "/System",
    "/Library",
    "/Applications",
    "/opt",
    "/etc",
};

/// Result type for safeguard checks
pub const SafeguardResult = union(enum) {
    ok: void,
    fatal_error: errors.FatalError,

    pub fn isOk(self: SafeguardResult) bool {
        return switch (self) {
            .ok => true,
            .fatal_error => false,
        };
    }
};

/// Check if a path is a large directory that should trigger a warning
/// Returns true if the path matches a known large directory
fn isLargeDirectory(path: []const u8, allocator: std.mem.Allocator) !bool {
    // Resolve to canonical path (handles symlinks, relative paths, etc.)
    const canonical = std.fs.cwd().realpathAlloc(allocator, path) catch |err| {
        // If we can't resolve the path, it might not exist or be inaccessible
        // In this case, we don't consider it a large directory
        switch (err) {
            error.FileNotFound, error.AccessDenied => return false,
            else => return err,
        }
    };
    defer allocator.free(canonical);

    // Check against known large directories (exact match)
    for (LARGE_DIRECTORIES) |large_dir| {
        if (std.mem.eql(u8, canonical, large_dir)) {
            return true;
        }
    }

    // Check if it's a user home directory (platform-specific)
    if (try isUserHomeDirectory(canonical, allocator)) {
        return true;
    }

    return false;
}

/// Check if a path is a user home directory
fn isUserHomeDirectory(canonical_path: []const u8, allocator: std.mem.Allocator) !bool {
    // Get the HOME environment variable
    const home = std.posix.getenv("HOME") orelse return false;

    // Resolve HOME to canonical path
    const canonical_home = std.fs.cwd().realpathAlloc(allocator, home) catch return false;
    defer allocator.free(canonical_home);

    // Compare paths
    return std.mem.eql(u8, canonical_path, canonical_home);
}

/// Check for large directory and return fatal error if detected and force is false
pub fn checkLargeDirectory(path: []const u8, force: bool, allocator: std.mem.Allocator) !SafeguardResult {
    const is_large = try isLargeDirectory(path, allocator);

    if (is_large and !force) {
        // Return fatal error
        return SafeguardResult{
            .fatal_error = errors.FatalError.init(
                .large_directory,
                path,
                "Refusing to traverse large directory that may contain thousands of files. Recommendations: (1) Use 'depth' parameter to limit traversal, (2) Use filters to reduce scope, (3) Use 'output_file' to save results, or (4) Set 'force: true' to proceed anyway.",
            ),
        };
    }

    return SafeguardResult{ .ok = {} };
}

/// Validate that a filename is valid UTF-8
/// Returns true if valid, false if invalid
pub fn isValidUtf8(filename: []const u8) bool {
    return std.unicode.utf8ValidateSlice(filename);
}

/// Check filename UTF-8 validity and return error entry if invalid
/// If force is false and invalid UTF-8 detected, returns fatal error
/// If force is true and invalid UTF-8 detected, returns non-fatal error entry
pub fn validateFilenameUtf8(
    path: []const u8,
    force: bool,
    allocator: std.mem.Allocator,
) !union(enum) {
    ok: void,
    fatal_error: errors.FatalError,
    error_entry: errors.ErrorEntry,
} {
    if (!isValidUtf8(path)) {
        if (!force) {
            // Fatal error - abort execution
            return .{
                .fatal_error = try errors.FatalError.init(
                    .non_utf8_filename,
                    path,
                    "Encountered filename with invalid UTF-8 encoding. This may indicate a legacy file, corrupted filesystem, or unusual naming. Use 'force: true' to skip this file and continue.",
                    allocator,
                ),
            };
        } else {
            // Non-fatal error - skip and continue
            const message = "Invalid UTF-8 encoding in filename (skipped due to force mode)";
            return .{
                .error_entry = try types.ErrorEntry.initAlloc(
                    .non_utf8_filename,
                    path,
                    message,
                    allocator,
                ),
            };
        }
    }

    return .{ .ok = {} };
}

/// Validate a directory path for traversal
/// Checks both large directory and basic path validity
pub fn validatePath(path: []const u8, force: bool, allocator: std.mem.Allocator) !SafeguardResult {
    // First check if it's a large directory
    const large_dir_result = try checkLargeDirectory(path, force, allocator);
    if (!large_dir_result.isOk()) {
        return large_dir_result;
    }

    // Check if path is valid UTF-8
    const utf8_result = try validateFilenameUtf8(path, force, allocator);
    switch (utf8_result) {
        .ok => {},
        .fatal_error => |fatal| return SafeguardResult{ .fatal_error = fatal },
        .error_entry => {
            // For path validation, we treat UTF-8 errors as fatal regardless
            // because we can't proceed with an invalid path
            // (individual filenames can be skipped, but not the root path)
            return SafeguardResult{
                .fatal_error = try errors.FatalError.init(
                    .non_utf8_filename,
                    path,
                    "Root directory path contains invalid UTF-8 encoding. Cannot proceed.",
                    allocator,
                ),
            };
        },
    }

    return SafeguardResult{ .ok = {} };
}

test "isValidUtf8 - valid strings" {
    try std.testing.expect(isValidUtf8("hello.txt"));
    try std.testing.expect(isValidUtf8("файл.txt")); // Cyrillic
    try std.testing.expect(isValidUtf8("文件.txt")); // Chinese
    try std.testing.expect(isValidUtf8("ファイル.txt")); // Japanese
    try std.testing.expect(isValidUtf8("test-file_123.txt"));
    try std.testing.expect(isValidUtf8("")); // Empty string is valid UTF-8
}

test "isValidUtf8 - invalid strings" {
    // Invalid UTF-8 sequences
    const invalid1 = [_]u8{ 0xFF, 0xFE };
    try std.testing.expect(!isValidUtf8(&invalid1));

    const invalid2 = [_]u8{ 0x80, 0x81 };
    try std.testing.expect(!isValidUtf8(&invalid2));
}

test "isLargeDirectory - system paths" {
    const allocator = std.testing.allocator;

    // Test root directory
    const is_root_large = try isLargeDirectory("/", allocator);
    try std.testing.expect(is_root_large);

    // Test /usr
    const is_usr_large = try isLargeDirectory("/usr", allocator);
    try std.testing.expect(is_usr_large);
}

test "isLargeDirectory - non-large paths" {
    const allocator = std.testing.allocator;

    // Test a typical project directory (should not be large)
    const is_tmp_large = try isLargeDirectory("/tmp/test", allocator);
    try std.testing.expect(!is_tmp_large);
}

test "checkLargeDirectory - with force false" {
    const allocator = std.testing.allocator;

    const result = try checkLargeDirectory("/", false, allocator);
    defer if (!result.isOk()) {
        result.fatal_error.deinit(allocator);
    };

    try std.testing.expect(!result.isOk());
    try std.testing.expect(result.fatal_error.err_type == .large_directory);
}

test "checkLargeDirectory - with force true" {
    const allocator = std.testing.allocator;

    const result = try checkLargeDirectory("/", true, allocator);
    try std.testing.expect(result.isOk());
}

test "validateFilenameUtf8 - valid filename" {
    const allocator = std.testing.allocator;

    const result = try validateFilenameUtf8("valid-file.txt", false, allocator);
    switch (result) {
        .ok => {},
        else => try std.testing.expect(false),
    }
}

test "validateFilenameUtf8 - invalid without force" {
    const allocator = std.testing.allocator;

    const invalid = [_]u8{ 'f', 'i', 'l', 'e', 0xFF, 0xFE };
    const result = try validateFilenameUtf8(&invalid, false, allocator);
    defer switch (result) {
        .fatal_error => |fatal| fatal.deinit(allocator),
        else => {},
    };

    switch (result) {
        .fatal_error => |fatal| {
            try std.testing.expect(fatal.err_type == .non_utf8_filename);
        },
        else => try std.testing.expect(false),
    }
}

test "validateFilenameUtf8 - invalid with force" {
    const allocator = std.testing.allocator;

    const invalid = [_]u8{ 'f', 'i', 'l', 'e', 0xFF, 0xFE };
    const result = try validateFilenameUtf8(&invalid, true, allocator);
    defer switch (result) {
        .error_entry => |*entry| entry.deinit(allocator),
        else => {},
    };

    switch (result) {
        .error_entry => |entry| {
            try std.testing.expect(entry.type == .non_utf8_filename);
        },
        else => try std.testing.expect(false),
    }
}
