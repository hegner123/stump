/// Pre-traversal validation: large-directory detection and UTF-8 filename checks.
///
/// Imported by tree.zig (checkLargeDirectory at traversal start, isValidUtf8
/// for each entry name). Delegates path classification to config.isLargeDirectory
/// and provides the SafeguardResult tagged union for clean ok/fatal_error branching.
const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const errors = @import("errors.zig");
const config = @import("config.zig");

// Re-export LARGE_DIRECTORIES for any code that expects it here
// (canonical definition is in config.zig)
pub const LARGE_DIRECTORIES = config.LARGE_DIRECTORIES;

/// Outcome of a pre-traversal safety check -- either ok or a fatal error.
///
/// Returned by checkLargeDirectory and validatePath. Callers in tree.buildTree
/// inspect isOk() and propagate error.LargeDirectory if the check fails.
pub const SafeguardResult = union(enum) {
    ok: void,
    fatal_error: types.FatalError,

    pub fn isOk(self: SafeguardResult) bool {
        return switch (self) {
            .ok => true,
            .fatal_error => false,
        };
    }
};

/// Guards against traversing known-massive directories (/, /usr, /home/user, etc.).
///
/// Called as the first operation in tree.buildTree. When force is true, the
/// check is bypassed and always returns ok. When the path matches a large
/// directory and force is false, returns a FatalError that main.executeStump
/// serializes as the tool error response.
pub fn checkLargeDirectory(path: []const u8, force: bool, allocator: std.mem.Allocator) !SafeguardResult {
    const is_large = try config.isLargeDirectory(allocator, path);

    if (is_large and !force) {
        // Return fatal error
        const message = "Refusing to traverse large directory that may contain thousands of files. Recommendations: (1) Use 'depth' parameter to limit traversal, (2) Use filters to reduce scope, (3) Use 'output_file' to save results, or (4) Set 'force: true' to proceed anyway.";
        return SafeguardResult{
            .fatal_error = try types.FatalError.init(
                allocator,
                .large_directory,
                path,
                message,
            ),
        };
    }

    return SafeguardResult{ .ok = {} };
}

/// Validates UTF-8 encoding of a filename byte slice.
///
/// Called by tree.processEntry for every directory entry before path
/// construction. Invalid filenames are either fatal (force=false) or
/// skipped with an error record (force=true).
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
    fatal_error: types.FatalError,
    error_entry: types.ErrorEntry,
} {
    if (!isValidUtf8(path)) {
        if (!force) {
            // Fatal error - abort execution
            const message = "Encountered filename with invalid UTF-8 encoding. This may indicate a legacy file, corrupted filesystem, or unusual naming. Use 'force: true' to skip this file and continue.";
            return .{
                .fatal_error = try types.FatalError.init(
                    allocator,
                    .non_utf8_filename,
                    path,
                    message,
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

/// Runs all pre-traversal validations (large directory + UTF-8 path encoding).
///
/// Composes checkLargeDirectory and validateFilenameUtf8 into a single call.
/// Not currently used in the main code path -- tree.buildTree calls
/// checkLargeDirectory directly. Available for callers that want both checks
/// in one operation.
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
            const message = "Root directory path contains invalid UTF-8 encoding. Cannot proceed.";
            return SafeguardResult{
                .fatal_error = try types.FatalError.init(
                    allocator,
                    .non_utf8_filename,
                    path,
                    message,
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
    if (comptime builtin.os.tag == .windows) {
        return error.SkipZigTest;
    }
    const allocator = std.testing.allocator;

    const is_root_large = try config.isLargeDirectory(allocator, "/");
    try std.testing.expect(is_root_large);

    const is_usr_large = try config.isLargeDirectory(allocator, "/usr");
    try std.testing.expect(is_usr_large);
}

test "isLargeDirectory - non-large paths" {
    if (comptime builtin.os.tag == .windows) {
        return error.SkipZigTest;
    }
    const allocator = std.testing.allocator;

    const is_tmp_large = config.isLargeDirectory(allocator, "/tmp/test") catch false;
    try std.testing.expect(!is_tmp_large);
}

test "checkLargeDirectory - with force false" {
    if (comptime builtin.os.tag == .windows) {
        return error.SkipZigTest;
    }
    const allocator = std.testing.allocator;

    var result = try checkLargeDirectory("/", false, allocator);
    defer if (!result.isOk()) {
        result.fatal_error.deinit(allocator);
    };

    try std.testing.expect(!result.isOk());
    try std.testing.expect(result.fatal_error.type == .large_directory);
}

test "checkLargeDirectory - with force true" {
    if (comptime builtin.os.tag == .windows) {
        return error.SkipZigTest;
    }
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
    var result = try validateFilenameUtf8(&invalid, false, allocator);
    defer switch (result) {
        .fatal_error => |*fatal| fatal.deinit(allocator),
        else => {},
    };

    switch (result) {
        .fatal_error => |fatal| {
            try std.testing.expect(fatal.type == .non_utf8_filename);
        },
        else => try std.testing.expect(false),
    }
}

test "validateFilenameUtf8 - invalid with force" {
    const allocator = std.testing.allocator;

    const invalid = [_]u8{ 'f', 'i', 'l', 'e', 0xFF, 0xFE };
    var result = try validateFilenameUtf8(&invalid, true, allocator);
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
