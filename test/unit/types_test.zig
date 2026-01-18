const std = @import("std");
const testing = std.testing;
const types = @import("../../src/types.zig");

test "EntryType.toChar returns correct characters" {
    try testing.expectEqual(@as(u8, 'f'), types.EntryType.file.toChar());
    try testing.expectEqual(@as(u8, 'd'), types.EntryType.directory.toChar());
    try testing.expectEqual(@as(u8, 's'), types.EntryType.symlink.toChar());
}

test "EntryType.toString returns correct strings" {
    try testing.expectEqualStrings("f", types.EntryType.file.toString());
    try testing.expectEqualStrings("d", types.EntryType.directory.toString());
    try testing.expectEqualStrings("s", types.EntryType.symlink.toString());
}

test "TreeEntry deinit frees allocated path" {
    const allocator = testing.allocator;

    const path = try allocator.dupe(u8, "test/path");
    var entry = types.TreeEntry{
        .path = path,
        .type = .file,
        .size = 1024,
    };

    entry.deinit(allocator);
    // No assertion needed - if memory isn't freed properly, the test will leak
}

test "TreeEntry without size" {
    const allocator = testing.allocator;

    const path = try allocator.dupe(u8, "test/directory");
    var entry = types.TreeEntry{
        .path = path,
        .type = .directory,
    };

    try testing.expect(entry.size == null);
    entry.deinit(allocator);
}

test "SymlinkInfo deinit frees both path and target" {
    const allocator = testing.allocator;

    const path = try allocator.dupe(u8, "test/link");
    const target = try allocator.dupe(u8, "../target");
    var info = types.SymlinkInfo{
        .path = path,
        .target = target,
    };

    info.deinit(allocator);
    // Memory leak detection will catch if either path or target isn't freed
}

test "ErrorType.isFatal identifies fatal errors correctly" {
    // Fatal errors
    try testing.expect(types.ErrorType.large_directory.isFatal());
    try testing.expect(types.ErrorType.non_utf8_filename.isFatal());
    try testing.expect(types.ErrorType.symlink_cycle.isFatal());

    // Non-fatal errors
    try testing.expect(!types.ErrorType.permission_denied.isFatal());
    try testing.expect(!types.ErrorType.invalid_symlink.isFatal());
    try testing.expect(!types.ErrorType.path_too_long.isFatal());
    try testing.expect(!types.ErrorType.unreadable_file.isFatal());
    try testing.expect(!types.ErrorType.token_limit_exceeded.isFatal());
    try testing.expect(!types.ErrorType.invalid_input.isFatal());
    try testing.expect(!types.ErrorType.unknown_error.isFatal());
}

test "ErrorType.toString returns correct string representations" {
    try testing.expectEqualStrings("large_directory", types.ErrorType.large_directory.toString());
    try testing.expectEqualStrings("non_utf8_filename", types.ErrorType.non_utf8_filename.toString());
    try testing.expectEqualStrings("symlink_cycle", types.ErrorType.symlink_cycle.toString());
    try testing.expectEqualStrings("permission_denied", types.ErrorType.permission_denied.toString());
    try testing.expectEqualStrings("invalid_symlink", types.ErrorType.invalid_symlink.toString());
    try testing.expectEqualStrings("path_too_long", types.ErrorType.path_too_long.toString());
    try testing.expectEqualStrings("unreadable_file", types.ErrorType.unreadable_file.toString());
    try testing.expectEqualStrings("token_limit_exceeded", types.ErrorType.token_limit_exceeded.toString());
    try testing.expectEqualStrings("invalid_input", types.ErrorType.invalid_input.toString());
    try testing.expectEqualStrings("unknown_error", types.ErrorType.unknown_error.toString());
}

test "ErrorEntry.init creates entry with correct fields" {
    const err_entry = types.ErrorEntry.init(
        .permission_denied,
        "/test/path",
        "Permission denied: cannot read directory"
    );

    try testing.expectEqual(types.ErrorType.permission_denied, err_entry.type);
    try testing.expectEqualStrings("/test/path", err_entry.path);
    try testing.expectEqualStrings("Permission denied: cannot read directory", err_entry.message);
    try testing.expect(err_entry.target == null);
}

test "ErrorEntry with target field" {
    var err_entry = types.ErrorEntry.init(
        .invalid_symlink,
        "/test/link",
        "Broken symbolic link"
    );
    err_entry.target = "/nonexistent/target";

    try testing.expectEqual(types.ErrorType.invalid_symlink, err_entry.type);
    try testing.expectEqualStrings("/test/link", err_entry.path);
    try testing.expectEqualStrings("Broken symbolic link", err_entry.message);
    try testing.expect(err_entry.target != null);
    try testing.expectEqualStrings("/nonexistent/target", err_entry.target.?);
}

test "ErrorEntry deinit frees allocated memory" {
    const allocator = testing.allocator;

    const path = try allocator.dupe(u8, "/test/path");
    const message = try allocator.dupe(u8, "Test error message");
    const target = try allocator.dupe(u8, "/test/target");

    var err_entry = types.ErrorEntry{
        .type = .invalid_symlink,
        .path = path,
        .message = message,
        .target = target,
    };

    err_entry.deinit(allocator);
    // Memory leak detection will catch if anything isn't freed
}

test "Statistics initialization" {
    const stats = types.Statistics{
        .dirs = 10,
        .files = 25,
        .filtered = 3,
        .symlinks = 2,
    };

    try testing.expectEqual(@as(u64, 10), stats.dirs);
    try testing.expectEqual(@as(u64, 25), stats.files);
    try testing.expectEqual(@as(u64, 3), stats.filtered);
    try testing.expectEqual(@as(u64, 2), stats.symlinks);
}
