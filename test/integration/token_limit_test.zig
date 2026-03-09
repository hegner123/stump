const std = @import("std");
const builtin = @import("builtin");
const stump = @import("stump");
const types = stump.types;
const tree = stump.tree;
const output = stump.output;

test "token limit enforcement - large directory" {
    const allocator = std.testing.allocator;

    // Test with very low token limit (should trigger limit)
    var config = types.Config{
        .dir = "test/fixtures/large",
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
        .token_limit = 1000, // Very low limit
        .sort = .none,
    };

    var state = try tree.buildTree(allocator, &config);
    defer state.deinit();

    // Try to build JSON output - should fail with token limit error
    const json_result = output.buildJsonOutput(allocator, &state, &config);

    if (json_result) |json| {
        defer allocator.free(json);
        // Should not succeed with such a low limit on large fixture
        try std.testing.expect(false);
    } else |err| {
        // Should get token limit exceeded error
        try std.testing.expectEqual(error.TokenLimitExceeded, err);
    }
}

test "token limit - parameter overrides default" {
    const allocator = std.testing.allocator;

    // Test with custom token limit
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
        .token_limit = 50000, // Custom limit
        .sort = .none,
    };

    var state = try tree.buildTree(allocator, &config);
    defer state.deinit();

    // Should succeed with reasonable limit on small fixture
    const json = try output.buildJsonOutput(allocator, &state, &config);
    defer allocator.free(json);

    try std.testing.expect(json.len > 0);
}

test "token limit - very high limit" {
    const allocator = std.testing.allocator;

    // Test with high token limit
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
        .token_limit = 100000, // High limit
        .sort = .none,
    };

    var state = try tree.buildTree(allocator, &config);
    defer state.deinit();

    const json = try output.buildJsonOutput(allocator, &state, &config);
    defer allocator.free(json);

    try std.testing.expect(json.len > 0);
}

test "no token limit with file output" {
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest;
    const allocator = std.testing.allocator;

    // When output_file is set, token_limit should not apply
    const temp_file = "/tmp/stump-test-output.json";
    var config = types.Config{
        .dir = "test/fixtures/large",
        .depth = -1,
        .include_ext = null,
        .exclude_ext = null,
        .exclude_patterns = null,
        .show_hidden = true,
        .show_size = true,
        .follow_symlinks = false,
        .force = false,
        .performance = false,
        .output_file = temp_file,
        .token_limit = null, // No limit for file mode
        .sort = .none,
    };

    var state = try tree.buildTree(allocator, &config);
    defer state.deinit();

    // Build and write to file
    const json = try output.buildJsonOutput(allocator, &state, &config);
    defer allocator.free(json);

    // Write to file
    const file = try std.fs.cwd().createFile(temp_file, .{});
    defer file.close();
    defer std.fs.cwd().deleteFile(temp_file) catch {};

    try file.writeAll(json);

    // Verify file was created and has content
    const stat = try std.fs.cwd().statFile(temp_file);
    try std.testing.expect(stat.size > 0);
}

test "token estimation accuracy" {
    const allocator = std.testing.allocator;

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
        .token_limit = 10000,
        .sort = .none,
    };

    var state = try tree.buildTree(allocator, &config);
    defer state.deinit();

    const json = try output.buildJsonOutput(allocator, &state, &config);
    defer allocator.free(json);

    // Token count should be roughly json.len / 4 (rough estimate)
    // This is a basic sanity check for the estimation
    const estimated_tokens = json.len / 4;
    try std.testing.expect(estimated_tokens > 0);
    try std.testing.expect(estimated_tokens < config.token_limit.?);
}
