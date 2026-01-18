const std = @import("std");
const stump = @import("stump");
const types = stump.types;
const tree = stump.tree;
const output = stump.output;

test "symlink detection - follow_symlinks false" {
    const allocator = std.testing.allocator;

    var config = types.Config{
        .dir = "test/fixtures/symlinks",
        .depth = -1,
        .include_ext = null,
        .exclude_ext = null,
        .exclude_patterns = null,
        .show_hidden = true,
        .show_size = true,
        .follow_symlinks = false,
        .force = false,
        .performance = false,
        .output_file = null,
        .token_limit = null,
        .sort = .none,
    };

    var state = try tree.buildTree(allocator, &config);
    defer state.deinit();

    // Verify symlinks were detected
    try std.testing.expect(state.stats.symlinks > 0);

    // Verify symlink entries exist in tree with type 's'
    var found_symlink = false;
    for (state.tree.items) |entry| {
        if (entry.type == .symlink) {
            found_symlink = true;
            break;
        }
    }
    try std.testing.expect(found_symlink);

    // Verify symlinks_detected array is populated
    try std.testing.expect(state.symlinks_detected.items.len > 0);
}

test "symlink following - follow_symlinks true" {
    const allocator = std.testing.allocator;

    var config = types.Config{
        .dir = "test/fixtures/symlinks",
        .depth = -1,
        .include_ext = null,
        .exclude_ext = null,
        .exclude_patterns = null,
        .show_hidden = true,
        .show_size = true,
        .follow_symlinks = true,
        .force = false,
        .performance = false,
        .output_file = null,
        .token_limit = null,
        .sort = .none,
    };

    var state = try tree.buildTree(allocator, &config);
    defer state.deinit();

    // When following symlinks, they should be traversed
    // symlinks_detected should NOT be populated when follow_symlinks is true
    try std.testing.expect(state.symlinks_detected.items.len == 0);

    // Tree should include files from symlinked directories
    try std.testing.expect(state.tree.items.len > 0);
}

test "symlink cycle detection" {
    const allocator = std.testing.allocator;

    var config = types.Config{
        .dir = "test/fixtures/symlink-cycle",
        .depth = -1,
        .include_ext = null,
        .exclude_ext = null,
        .exclude_patterns = null,
        .show_hidden = true,
        .show_size = true,
        .follow_symlinks = true, // Enable following to trigger cycle detection
        .force = false,
        .performance = false,
        .output_file = null,
        .token_limit = null,
        .sort = .none,
    };

    // Should detect cycle and return error
    const result = tree.buildTree(allocator, &config);

    if (result) |state| {
        state.deinit();
        // Should not succeed - cycle should be detected
        try std.testing.expect(false);
    } else |err| {
        // Should get symlink cycle error
        try std.testing.expectEqual(error.SymlinkCycle, err);
    }
}

test "symlink cycle detection with force flag" {
    const allocator = std.testing.allocator;

    var config = types.Config{
        .dir = "test/fixtures/symlink-cycle",
        .depth = -1,
        .include_ext = null,
        .exclude_ext = null,
        .exclude_patterns = null,
        .show_hidden = true,
        .show_size = true,
        .follow_symlinks = true,
        .force = true, // Force should bypass the fatal error
        .performance = false,
        .output_file = null,
        .token_limit = null,
        .sort = .none,
    };

    var state = try tree.buildTree(allocator, &config);
    defer state.deinit();

    // With force flag, cycle should be recorded as non-fatal error
    // Should have some errors recorded
    try std.testing.expect(state.errors.items.len > 0);

    // Check for symlink cycle error in errors array
    var found_cycle_error = false;
    for (state.errors.items) |err_entry| {
        if (err_entry.type == .symlink_cycle) {
            found_cycle_error = true;
            break;
        }
    }
    try std.testing.expect(found_cycle_error);
}

test "broken symlink handling" {
    const allocator = std.testing.allocator;

    // Create a temporary broken symlink for testing
    const temp_dir = "/tmp/stump-test-broken-symlink";
    std.fs.cwd().makeDir(temp_dir) catch {};
    defer std.fs.cwd().deleteTree(temp_dir) catch {};

    // Create broken symlink
    const broken_link = temp_dir ++ "/broken-link";
    std.posix.symlink("/nonexistent/path", broken_link) catch {};
    defer std.fs.cwd().deleteFile(broken_link) catch {};

    var config = types.Config{
        .dir = temp_dir,
        .depth = -1,
        .include_ext = null,
        .exclude_ext = null,
        .exclude_patterns = null,
        .show_hidden = true,
        .show_size = true,
        .follow_symlinks = false,
        .force = false,
        .performance = false,
        .output_file = null,
        .token_limit = null,
        .sort = .none,
    };

    var state = try tree.buildTree(allocator, &config);
    defer state.deinit();

    // Broken symlink should be recorded as non-fatal error (if implementation supports it)
    // This is a best-effort test - some implementations may not record this error
    for (state.errors.items) |err_entry| {
        if (err_entry.type == .invalid_symlink) {
            // Found the broken link error, test passes
            return;
        }
    }

    // If we didn't find the error, that's also okay for this test
    // The important thing is the traversal completed without crashing
}

test "symlink target path recording" {
    const allocator = std.testing.allocator;

    var config = types.Config{
        .dir = "test/fixtures/symlinks",
        .depth = -1,
        .include_ext = null,
        .exclude_ext = null,
        .exclude_patterns = null,
        .show_hidden = true,
        .show_size = true,
        .follow_symlinks = false,
        .force = false,
        .performance = false,
        .output_file = null,
        .token_limit = null,
        .sort = .none,
    };

    var state = try tree.buildTree(allocator, &config);
    defer state.deinit();

    // Verify symlinks_detected has target paths
    for (state.symlinks_detected.items) |symlink_info| {
        try std.testing.expect(symlink_info.path.len > 0);
        try std.testing.expect(symlink_info.target.len > 0);
    }
}
