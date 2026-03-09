const std = @import("std");
const builtin = @import("builtin");
const stump = @import("stump");
const types = stump.types;
const tree = stump.tree;
const output = stump.output;

test "JSON output structure" {
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
        .token_limit = null,
        .sort = .none,
    };

    var state = try tree.buildTree(allocator, &config);
    defer state.deinit();

    const json = try output.buildJsonOutput(allocator, &state, &config);
    defer allocator.free(json);

    // Verify JSON is valid
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    // Verify required fields exist
    try std.testing.expect(parsed.value.object.get("root") != null);
    try std.testing.expect(parsed.value.object.get("depth") != null);
    try std.testing.expect(parsed.value.object.get("stats") != null);
    try std.testing.expect(parsed.value.object.get("tree") != null);

    // Verify stats structure
    const stats = parsed.value.object.get("stats").?;
    try std.testing.expect(stats.object.get("dirs") != null);
    try std.testing.expect(stats.object.get("files") != null);
    try std.testing.expect(stats.object.get("filtered") != null);
    try std.testing.expect(stats.object.get("symlinks") != null);

    // Verify tree is an array
    const tree_array = parsed.value.object.get("tree").?;
    try std.testing.expect(tree_array == .array);
}

test "JSON output with symlinks detected" {
    const allocator = std.testing.allocator;

    var config = types.Config{
        .dir = "test/fixtures/symlinks",
        .depth = -1,
        .include_ext = null,
        .exclude_ext = null,
        .exclude_patterns = null,
        .show_hidden = true,
        .show_size = true,
        .follow_symlinks = false, // Don't follow to populate symlinks_detected
        .force = false,
        .performance = false,
        .output_file = null,
        .token_limit = null,
        .sort = .none,
    };

    var state = try tree.buildTree(allocator, &config);
    defer state.deinit();

    const json = try output.buildJsonOutput(allocator, &state, &config);
    defer allocator.free(json);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    // symlinks_detected should exist when symlinks found and follow_symlinks is false
    const symlinks_detected = parsed.value.object.get("symlinks_detected");
    if (state.symlinks_detected.items.len > 0) {
        try std.testing.expect(symlinks_detected != null);
        try std.testing.expect(symlinks_detected.? == .array);
        try std.testing.expect(symlinks_detected.?.array.items.len > 0);
    }
}

test "JSON output with errors" {
    const allocator = std.testing.allocator;

    // Use a path that might have permission issues or create one
    // For testing, we'll use force flag which adds a note
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

    var state = try tree.buildTree(allocator, &config);
    defer state.deinit();

    const json = try output.buildJsonOutput(allocator, &state, &config);
    defer allocator.free(json);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    // errors field should only exist if there are errors
    const errors_field = parsed.value.object.get("errors");
    if (state.errors.items.len > 0) {
        try std.testing.expect(errors_field != null);
    }
}

test "JSON output with performance metrics" {
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
        .performance = true, // Enable performance
        .output_file = null,
        .token_limit = null,
        .sort = .none,
    };

    var state = try tree.buildTree(allocator, &config);
    defer state.deinit();

    const json = try output.buildJsonOutput(allocator, &state, &config);
    defer allocator.free(json);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    // performance field should exist when performance: true
    const perf = parsed.value.object.get("performance");
    try std.testing.expect(perf != null);

    // Verify performance structure
    try std.testing.expect(perf.?.object.get("readdir_calls") != null);
    try std.testing.expect(perf.?.object.get("stat_calls") != null);
}

test "JSON output with force flag note" {
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
        .force = true, // Enable force flag
        .performance = false,
        .output_file = null,
        .token_limit = null,
        .sort = .none,
    };

    var state = try tree.buildTree(allocator, &config);
    defer state.deinit();

    const json = try output.buildJsonOutput(allocator, &state, &config);
    defer allocator.free(json);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    // _note field should exist when force: true
    const note = parsed.value.object.get("_note");
    try std.testing.expect(note != null);
    try std.testing.expect(note.? == .string);
}

test "file output mode" {
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest;
    const allocator = std.testing.allocator;

    const temp_file = "/tmp/stump-test-file-output.json";
    defer std.fs.cwd().deleteFile(temp_file) catch {};

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
        .output_file = temp_file,
        .token_limit = null,
        .sort = .none,
    };

    var state = try tree.buildTree(allocator, &config);
    defer state.deinit();

    const json = try output.buildJsonOutput(allocator, &state, &config);
    defer allocator.free(json);

    // Write to file
    const file = try std.fs.cwd().createFile(temp_file, .{});
    defer file.close();

    try file.writeAll(json);

    // Verify file exists and has content
    const written_content = try std.fs.cwd().readFileAlloc(allocator, temp_file, 10 * 1024 * 1024);
    defer allocator.free(written_content);

    try std.testing.expect(written_content.len > 0);

    // Verify content is valid JSON
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, written_content, .{});
    defer parsed.deinit();

    try std.testing.expect(parsed.value.object.get("root") != null);
}

test "tree entry types" {
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
        .token_limit = null,
        .sort = .none,
    };

    var state = try tree.buildTree(allocator, &config);
    defer state.deinit();

    const json = try output.buildJsonOutput(allocator, &state, &config);
    defer allocator.free(json);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    const tree_array = parsed.value.object.get("tree").?.array;

    // Verify each entry has path and type
    for (tree_array.items) |entry| {
        try std.testing.expect(entry.object.get("path") != null);
        try std.testing.expect(entry.object.get("type") != null);

        const entry_type = entry.object.get("type").?.string;
        // Type should be 'f', 'd', or 's'
        try std.testing.expect(
            std.mem.eql(u8, entry_type, "f") or
                std.mem.eql(u8, entry_type, "d") or
                std.mem.eql(u8, entry_type, "s"),
        );

        // Files should have size field
        if (std.mem.eql(u8, entry_type, "f")) {
            try std.testing.expect(entry.object.get("size") != null);
        }
    }
}

test "JSON output compactness" {
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
        .token_limit = null,
        .sort = .none,
    };

    var state = try tree.buildTree(allocator, &config);
    defer state.deinit();

    const json = try output.buildJsonOutput(allocator, &state, &config);
    defer allocator.free(json);

    // JSON should be compact (no unnecessary whitespace)
    // Check that there are no multiple consecutive spaces
    var consecutive_spaces = false;
    var i: usize = 0;
    while (i < json.len - 1) : (i += 1) {
        if (json[i] == ' ' and json[i + 1] == ' ') {
            consecutive_spaces = true;
            break;
        }
    }
    try std.testing.expect(!consecutive_spaces);
}
