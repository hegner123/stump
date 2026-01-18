const std = @import("std");
const stump = @import("stump");
const types = stump.types;
const tree = stump.tree;
const output = stump.output;

test "basic directory traversal" {
    const allocator = std.testing.allocator;

    // Create config for basic fixture
    var config = types.Config{
        .dir = "test/fixtures/basic",
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

    // Build the tree
    var state = try tree.buildTree(allocator, &config);
    defer state.deinit();

    // Verify we have expected structure
    // basic/ has: .hidden, file1.txt, subdir1/file2.txt, subdir2/file3.txt
    try std.testing.expect(state.stats.files >= 3); // At least the 3 visible files
    try std.testing.expect(state.stats.dirs >= 2); // subdir1 and subdir2

    // Check that hidden file is included (show_hidden: true)
    var found_hidden = false;
    for (state.tree.items) |entry| {
        if (std.mem.indexOf(u8, entry.path, ".hidden") != null) {
            found_hidden = true;
            break;
        }
    }
    try std.testing.expect(found_hidden);
}

test "deep directory traversal with depth limit" {
    const allocator = std.testing.allocator;

    // Test without depth limit
    var config_unlimited = types.Config{
        .dir = "test/fixtures/deep",
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

    var state_unlimited = try tree.buildTree(allocator, &config_unlimited);
    defer state_unlimited.deinit();

    const unlimited_count = state_unlimited.tree.items.len;
    try std.testing.expect(unlimited_count > 10); // Should have deep nesting

    // Test with depth limit of 3
    var config_limited = types.Config{
        .dir = "test/fixtures/deep",
        .depth = 3,
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

    var state_limited = try tree.buildTree(allocator, &config_limited);
    defer state_limited.deinit();

    const limited_count = state_limited.tree.items.len;
    try std.testing.expect(limited_count < unlimited_count); // Should be less with limit
    try std.testing.expect(limited_count <= 4); // At most 4 levels (0,1,2,3)
}

test "wide directory traversal" {
    const allocator = std.testing.allocator;

    var config = types.Config{
        .dir = "test/fixtures/wide",
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

    // Wide fixture has 100 files
    try std.testing.expect(state.stats.files >= 100);
}

test "hidden files filtering" {
    const allocator = std.testing.allocator;

    // Test with hidden files shown
    var config_shown = types.Config{
        .dir = "test/fixtures/basic",
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

    var state_shown = try tree.buildTree(allocator, &config_shown);
    defer state_shown.deinit();

    var hidden_count_shown: usize = 0;
    for (state_shown.tree.items) |entry| {
        const basename = std.fs.path.basename(entry.path);
        if (basename.len > 0 and basename[0] == '.') {
            hidden_count_shown += 1;
        }
    }

    // Test with hidden files hidden
    var config_hidden = types.Config{
        .dir = "test/fixtures/basic",
        .depth = -1,
        .include_ext = null,
        .exclude_ext = null,
        .exclude_patterns = null,
        .show_hidden = false,
        .show_size = true,
        .follow_symlinks = false,
        .force = false,
        .performance = false,
        .output_file = null,
        .token_limit = null,
        .sort = .none,
    };

    var state_hidden = try tree.buildTree(allocator, &config_hidden);
    defer state_hidden.deinit();

    var hidden_count_hidden: usize = 0;
    for (state_hidden.tree.items) |entry| {
        const basename = std.fs.path.basename(entry.path);
        if (basename.len > 0 and basename[0] == '.') {
            hidden_count_hidden += 1;
        }
    }

    // Should have fewer hidden files when show_hidden is false
    try std.testing.expect(hidden_count_shown > hidden_count_hidden);
}

test "extension filtering - include" {
    const allocator = std.testing.allocator;

    // Create filter for .txt files only
    var include_list = [_][]const u8{".txt"};
    var config = types.Config{
        .dir = "test/fixtures/mixed",
        .depth = -1,
        .include_ext = &include_list,
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

    // Verify all file entries have .txt extension
    for (state.tree.items) |entry| {
        if (entry.type == .file) {
            try std.testing.expect(std.mem.endsWith(u8, entry.path, ".txt"));
        }
    }
}

test "extension filtering - exclude" {
    const allocator = std.testing.allocator;

    // Exclude .json files
    var exclude_list = [_][]const u8{".json"};
    var config = types.Config{
        .dir = "test/fixtures/mixed",
        .depth = -1,
        .include_ext = null,
        .exclude_ext = &exclude_list,
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

    // Verify no file entries have .json extension
    for (state.tree.items) |entry| {
        if (entry.type == .file) {
            try std.testing.expect(!std.mem.endsWith(u8, entry.path, ".json"));
        }
    }
}

test "pattern filtering - exclude" {
    const allocator = std.testing.allocator;

    // Exclude files containing "test"
    var exclude_patterns = [_][]const u8{"test"};
    var config = types.Config{
        .dir = "test/fixtures/mixed",
        .depth = -1,
        .include_ext = null,
        .exclude_ext = null,
        .exclude_patterns = &exclude_patterns,
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

    // Verify no entries contain "test" in path
    for (state.tree.items) |entry| {
        try std.testing.expect(std.mem.indexOf(u8, entry.path, "test") == null);
    }
}

test "UTF-8 filename handling" {
    const allocator = std.testing.allocator;

    var config = types.Config{
        .dir = "test/fixtures/utf8",
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

    // UTF-8 fixture should have various international filenames
    try std.testing.expect(state.tree.items.len > 0);

    // All paths should be valid UTF-8
    for (state.tree.items) |entry| {
        try std.testing.expect(std.unicode.utf8ValidateSlice(entry.path));
    }
}
