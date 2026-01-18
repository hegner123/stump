const std = @import("std");
const testing = std.testing;
const errors = @import("../../src/errors.zig");
const types = @import("../../src/types.zig");

test "isValidUtf8 accepts valid UTF-8 strings" {
    try testing.expect(errors.isValidUtf8("hello"));
    try testing.expect(errors.isValidUtf8("test/path/file.txt"));
    try testing.expect(errors.isValidUtf8("测试"));
    try testing.expect(errors.isValidUtf8("hello 世界"));
    try testing.expect(errors.isValidUtf8(""));
}

test "isValidUtf8 rejects invalid UTF-8 sequences" {
    // Invalid UTF-8 byte sequences
    const invalid1 = [_]u8{ 0xFF, 0xFE };
    try testing.expect(!errors.isValidUtf8(&invalid1));

    const invalid2 = [_]u8{ 0xC0, 0x80 }; // Overlong encoding
    try testing.expect(!errors.isValidUtf8(&invalid2));
}

test "FatalError.init creates correct structure for large_directory" {
    const err = types.FatalError.init(.large_directory, "/usr", "Test message");

    try testing.expectEqualStrings("Large directory detected", err.@"error");
    try testing.expectEqualStrings("large_directory", err.type);
    try testing.expect(err.path != null);
    try testing.expectEqualStrings("/usr", err.path.?);
    try testing.expectEqualStrings("Test message", err.message);
}

test "FatalError.init creates correct structure for non_utf8_filename" {
    const err = types.FatalError.init(.non_utf8_filename, "/bad/file", "Test message");

    try testing.expectEqualStrings("Invalid filename encoding", err.@"error");
    try testing.expectEqualStrings("non_utf8_filename", err.type);
    try testing.expect(err.path != null);
    try testing.expectEqualStrings("/bad/file", err.path.?);
}

test "FatalError.init creates correct structure for symlink_cycle" {
    const err = types.FatalError.init(.symlink_cycle, "/link/cycle", "Test message");

    try testing.expectEqualStrings("Symlink cycle detected", err.@"error");
    try testing.expectEqualStrings("symlink_cycle", err.type);
    try testing.expect(err.path != null);
    try testing.expectEqualStrings("/link/cycle", err.path.?);
}

test "FatalError.init handles null path" {
    const err = types.FatalError.init(.large_directory, null, "Test message");

    try testing.expectEqualStrings("Large directory detected", err.@"error");
    try testing.expect(err.path == null);
}

test "buildLargeDirectoryError creates valid error" {
    const allocator = testing.allocator;

    const err = try errors.buildLargeDirectoryError(allocator, "/usr");
    defer allocator.free(err.message);

    try testing.expectEqualStrings("Large directory detected", err.@"error");
    try testing.expectEqualStrings("large_directory", err.type);
    try testing.expect(err.path != null);
    try testing.expectEqualStrings("/usr", err.path.?);
    try testing.expect(std.mem.indexOf(u8, err.message, "force: true") != null);
}

test "buildNonUtf8Error creates valid error" {
    const allocator = testing.allocator;

    const err = try errors.buildNonUtf8Error(allocator, "/bad/file");
    defer allocator.free(err.message);

    try testing.expectEqualStrings("Invalid filename encoding", err.@"error");
    try testing.expectEqualStrings("non_utf8_filename", err.type);
    try testing.expect(std.mem.indexOf(u8, err.message, "UTF-8") != null);
}

test "buildSymlinkCycleError creates valid error" {
    const allocator = testing.allocator;

    const err = try errors.buildSymlinkCycleError(allocator, "/link/cycle");
    defer allocator.free(err.message);

    try testing.expectEqualStrings("Symlink cycle detected", err.@"error");
    try testing.expectEqualStrings("symlink_cycle", err.type);
    try testing.expect(std.mem.indexOf(u8, err.message, "cycle") != null);
}

test "buildTokenLimitError creates valid error JSON" {
    const allocator = testing.allocator;

    const result = try errors.buildTokenLimitError(allocator, 10, 50, 5000, 10000);
    defer result.object.deinit();

    try testing.expect(result == .object);

    const error_field = result.object.get("error").?;
    try testing.expectEqualStrings("Token limit exceeded", error_field.string);

    const message_field = result.object.get("message").?;
    try testing.expect(std.mem.indexOf(u8, message_field.string, "10000") != null);
    try testing.expect(std.mem.indexOf(u8, message_field.string, "output_file") != null);

    const stats = result.object.get("stats").?.object;
    try testing.expectEqual(@as(i64, 10), stats.get("dirs").?.integer);
    try testing.expectEqual(@as(i64, 50), stats.get("files").?.integer);
    try testing.expectEqual(@as(i64, 5000), stats.get("aborted_at").?.integer);
    try testing.expectEqual(@as(i64, 10000), stats.get("token_limit").?.integer);
}

test "permissionDeniedMessage returns expected message" {
    const allocator = testing.allocator;

    const msg = try errors.permissionDeniedMessage(allocator, "/test/path");
    try testing.expectEqualStrings("Permission denied", msg);
}

test "invalidSymlinkMessage returns expected message" {
    const allocator = testing.allocator;

    const msg = try errors.invalidSymlinkMessage(allocator, "/target");
    try testing.expectEqualStrings("Target does not exist", msg);
}

test "pathTooLongMessage returns expected message" {
    const allocator = testing.allocator;

    const msg = try errors.pathTooLongMessage(allocator);
    try testing.expectEqualStrings("Path exceeds OS limit", msg);
}

test "unreadableFileMessage returns expected message" {
    const allocator = testing.allocator;

    const msg = try errors.unreadableFileMessage(allocator);
    try testing.expectEqualStrings("File exists but cannot be read", msg);
}

test "invalidInputMessage formats message correctly" {
    const allocator = testing.allocator;

    const msg = try errors.invalidInputMessage(allocator, "depth must be positive");
    defer allocator.free(msg);

    try testing.expectEqualStrings("Invalid input: depth must be positive", msg);
}

test "createPermissionDeniedError creates valid error entry" {
    const allocator = testing.allocator;

    const err = try errors.createPermissionDeniedError(allocator, "/test/path");

    try testing.expectEqual(types.ErrorType.permission_denied, err.type);
    try testing.expectEqualStrings("/test/path", err.path);
    try testing.expectEqualStrings("Permission denied", err.message);
    try testing.expect(err.target == null);
}

test "createInvalidSymlinkError creates valid error entry with target" {
    const allocator = testing.allocator;

    const err = try errors.createInvalidSymlinkError(allocator, "/link", "/target");

    try testing.expectEqual(types.ErrorType.invalid_symlink, err.type);
    try testing.expectEqualStrings("/link", err.path);
    try testing.expect(err.target != null);
    try testing.expectEqualStrings("/target", err.target.?);
    try testing.expectEqualStrings("Target does not exist", err.message);
}

test "createPathTooLongError creates valid error entry" {
    const allocator = testing.allocator;

    const err = try errors.createPathTooLongError(allocator, "/very/long/path");

    try testing.expectEqual(types.ErrorType.path_too_long, err.type);
    try testing.expectEqualStrings("/very/long/path", err.path);
    try testing.expectEqualStrings("Path exceeds OS limit", err.message);
}

test "createUnreadableFileError creates valid error entry" {
    const allocator = testing.allocator;

    const err = try errors.createUnreadableFileError(allocator, "/unreadable");

    try testing.expectEqual(types.ErrorType.unreadable_file, err.type);
    try testing.expectEqualStrings("/unreadable", err.path);
    try testing.expectEqualStrings("File exists but cannot be read", err.message);
}
