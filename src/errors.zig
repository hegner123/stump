const std = @import("std");
const types = @import("types.zig");

// Re-export types for convenience (canonical definitions are in types.zig)
pub const ErrorType = types.ErrorType;
pub const ErrorEntry = types.ErrorEntry;

/// Build fatal error message for large directory
pub fn buildLargeDirectoryError(allocator: std.mem.Allocator, path: []const u8) !types.FatalError {
    const message = try std.fmt.allocPrint(
        allocator,
        "Refusing to traverse large directory that may contain thousands of files. Recommendations: (1) Use 'depth' parameter to limit traversal, (2) Use filters to reduce scope, (3) Use 'output_file' to save results, or (4) Set 'force: true' to proceed anyway.",
        .{},
    );
    defer allocator.free(message); // FatalError.init will duplicate it

    return try types.FatalError.init(allocator, .large_directory, path, message);
}

/// Build fatal error message for non-UTF8 filename
pub fn buildNonUtf8Error(allocator: std.mem.Allocator, path: []const u8) !types.FatalError {
    const message = try std.fmt.allocPrint(
        allocator,
        "Encountered filename with invalid UTF-8 encoding. This may indicate a legacy file, corrupted filesystem, or unusual naming. Use 'force: true' to skip this file and continue.",
        .{},
    );
    defer allocator.free(message); // FatalError.init will duplicate it

    return try types.FatalError.init(allocator, .non_utf8_filename, path, message);
}

/// Build fatal error message for symlink cycle
pub fn buildSymlinkCycleError(allocator: std.mem.Allocator, path: []const u8) !types.FatalError {
    const message = try std.fmt.allocPrint(
        allocator,
        "Detected symlink cycle at this path. This would cause infinite traversal. Use 'force: true' to skip this symlink and continue, or disable 'follow_symlinks'.",
        .{},
    );
    defer allocator.free(message); // FatalError.init will duplicate it

    return try types.FatalError.init(allocator, .symlink_cycle, path, message);
}

/// Build token limit exceeded error
pub fn buildTokenLimitError(allocator: std.mem.Allocator, dirs: usize, files: usize, aborted_at: usize, token_limit: usize) !std.json.Value {
    const message = try std.fmt.allocPrint(
        allocator,
        "Tree output would exceed token limit ({d} tokens, ~{d} bytes). Use 'output_file' parameter to save to file instead, or increase 'token_limit' (range: 1000-100000).",
        .{ token_limit, aborted_at },
    );

    var stats = std.json.ObjectMap.init(allocator);
    try stats.put("dirs", .{ .integer = @intCast(dirs) });
    try stats.put("files", .{ .integer = @intCast(files) });
    try stats.put("aborted_at", .{ .integer = @intCast(aborted_at) });
    try stats.put("token_limit", .{ .integer = @intCast(token_limit) });

    var obj = std.json.ObjectMap.init(allocator);
    try obj.put("error", .{ .string = "Token limit exceeded" });
    try obj.put("message", .{ .string = message });
    try obj.put("stats", .{ .object = stats });

    return .{ .object = obj };
}

/// Format error message for permission denied
pub fn permissionDeniedMessage(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    _ = allocator;
    _ = path;
    return "Permission denied";
}

/// Format error message for invalid symlink
pub fn invalidSymlinkMessage(allocator: std.mem.Allocator, target: []const u8) ![]const u8 {
    _ = allocator;
    _ = target;
    return "Target does not exist";
}

/// Format error message for path too long
pub fn pathTooLongMessage(allocator: std.mem.Allocator) ![]const u8 {
    _ = allocator;
    return "Path exceeds OS limit";
}

/// Format error message for unreadable file
pub fn unreadableFileMessage(allocator: std.mem.Allocator) ![]const u8 {
    _ = allocator;
    return "File exists but cannot be read";
}

/// Format error message for invalid input
pub fn invalidInputMessage(allocator: std.mem.Allocator, details: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "Invalid input: {s}", .{details});
}

/// Validate UTF-8 encoding of a string
pub fn isValidUtf8(bytes: []const u8) bool {
    return std.unicode.utf8ValidateSlice(bytes);
}

/// Create a non-fatal error entry for permission denied
pub fn createPermissionDeniedError(allocator: std.mem.Allocator, path: []const u8) !types.ErrorEntry {
    const msg = try permissionDeniedMessage(allocator, path);
    return types.ErrorEntry.init(.permission_denied, path, msg);
}

/// Create a non-fatal error entry for invalid symlink
pub fn createInvalidSymlinkError(allocator: std.mem.Allocator, path: []const u8, target: []const u8) !types.ErrorEntry {
    const msg = try invalidSymlinkMessage(allocator, target);
    return types.ErrorEntry.initWithTarget(.invalid_symlink, path, target, msg);
}

/// Create a non-fatal error entry for path too long
pub fn createPathTooLongError(allocator: std.mem.Allocator, path: []const u8) !types.ErrorEntry {
    const msg = try pathTooLongMessage(allocator);
    return types.ErrorEntry.init(.path_too_long, path, msg);
}

/// Create a non-fatal error entry for unreadable file
pub fn createUnreadableFileError(allocator: std.mem.Allocator, path: []const u8) !types.ErrorEntry {
    const msg = try unreadableFileMessage(allocator);
    return types.ErrorEntry.init(.unreadable_file, path, msg);
}
