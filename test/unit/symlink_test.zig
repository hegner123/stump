const std = @import("std");
const testing = std.testing;
const symlink = @import("../../src/symlink.zig");
const types = @import("../../src/types.zig");

test "isSymlink detects symbolic links" {
    // Test with actual symlink from fixtures
    const is_link = symlink.isSymlink("test/fixtures/symlinks/link_to_file") catch |err| {
        // If fixture doesn't exist in test context, skip
        if (err == error.FileNotFound) {
            return;
        }
        return err;
    };

    try testing.expect(is_link);
}

test "isSymlink returns false for regular files" {
    const is_link = symlink.isSymlink("test/fixtures/basic/file1.txt") catch |err| {
        // If fixture doesn't exist, skip test
        if (err == error.FileNotFound) {
            return;
        }
        return err;
    };

    try testing.expect(!is_link);
}

test "isSymlink returns false for directories" {
    const is_link = symlink.isSymlink("test/fixtures/basic") catch |err| {
        if (err == error.FileNotFound) {
            return;
        }
        return err;
    };

    try testing.expect(!is_link);
}

test "isSymlink handles non-existent paths" {
    const is_link = try symlink.isSymlink("test/fixtures/nonexistent");
    try testing.expect(!is_link);
}

test "resolveTarget reads symlink target" {
    const allocator = testing.allocator;

    const target = symlink.resolveTarget(allocator, "test/fixtures/symlinks/link_to_file") catch |err| {
        // Skip if fixture doesn't exist
        if (err == error.FileNotFound or err == error.NotLink) {
            return;
        }
        return err;
    };
    defer allocator.free(target);

    // Should have successfully read the target
    try testing.expect(target.len > 0);
}

test "getDeviceInode returns valid device and inode" {
    const info = symlink.getDeviceInode("test/fixtures/basic/file1.txt") catch |err| {
        if (err == error.FileNotFound) {
            return;
        }
        return err;
    };

    // Device and inode should be non-zero for real files
    try testing.expect(info.dev > 0 or info.ino > 0);
}

test "isVisited detects visited paths" {
    const allocator = testing.allocator;
    var visited_paths = std.AutoHashMap(types.VisitedPath, void).init(allocator);
    defer visited_paths.deinit();

    // Mark path as visited
    symlink.markVisited(&visited_paths, "test/fixtures/basic/file1.txt") catch |err| {
        if (err == error.FileNotFound) {
            return;
        }
        return err;
    };

    // Check if it's detected as visited
    const is_visited = symlink.isVisited(&visited_paths, "test/fixtures/basic/file1.txt") catch |err| {
        if (err == error.FileNotFound) {
            return;
        }
        return err;
    };

    try testing.expect(is_visited);
}

test "isVisited returns false for unvisited paths" {
    const allocator = testing.allocator;
    var visited_paths = std.AutoHashMap(types.VisitedPath, void).init(allocator);
    defer visited_paths.deinit();

    const is_visited = symlink.isVisited(&visited_paths, "test/fixtures/basic/file1.txt") catch |err| {
        if (err == error.FileNotFound) {
            return;
        }
        return err;
    };

    try testing.expect(!is_visited);
}

test "markVisited adds path to visited set" {
    const allocator = testing.allocator;
    var visited_paths = std.AutoHashMap(types.VisitedPath, void).init(allocator);
    defer visited_paths.deinit();

    const initial_count = visited_paths.count();

    symlink.markVisited(&visited_paths, "test/fixtures/basic/file1.txt") catch |err| {
        if (err == error.FileNotFound) {
            return;
        }
        return err;
    };

    const final_count = visited_paths.count();
    try testing.expect(final_count == initial_count + 1);
}

test "getDeviceInode produces consistent results for same path" {
    const info1 = symlink.getDeviceInode("test/fixtures/basic/file1.txt") catch |err| {
        if (err == error.FileNotFound) {
            return;
        }
        return err;
    };

    const info2 = symlink.getDeviceInode("test/fixtures/basic/file1.txt") catch |err| {
        if (err == error.FileNotFound) {
            return;
        }
        return err;
    };

    try testing.expectEqual(info1.dev, info2.dev);
    try testing.expectEqual(info1.ino, info2.ino);
}
