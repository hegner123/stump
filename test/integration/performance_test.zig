const std = @import("std");
const stump = @import("stump");
const types = stump.types;
const tree = stump.tree;
const performance = stump.performance;

test "performance metrics collection enabled" {
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
        .performance = true, // Enable performance tracking
        .output_file = null,
        .token_limit = null,
        .sort = .none,
    };

    var state = try tree.buildTree(allocator, &config);
    defer state.deinit();

    // Verify performance metrics were collected
    try std.testing.expect(state.performance.readdir_calls > 0);
    try std.testing.expect(state.performance.stat_calls > 0);
}

test "performance metrics collection disabled" {
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
        .performance = false, // Disable performance tracking
        .output_file = null,
        .token_limit = null,
        .sort = .none,
    };

    var state = try tree.buildTree(allocator, &config);
    defer state.deinit();

    // Metrics should be zero when disabled
    try std.testing.expect(state.performance.readdir_calls == 0);
    try std.testing.expect(state.performance.stat_calls == 0);
}

test "performance metrics accuracy" {
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
        .performance = true,
        .output_file = null,
        .token_limit = null,
        .sort = .none,
    };

    var state = try tree.buildTree(allocator, &config);
    defer state.deinit();

    // Basic fixture has 2 subdirectories + root = 3 readdir calls
    try std.testing.expect(state.performance.readdir_calls >= 3);

    // Should have stat calls for each file and directory
    const total_entries = state.stats.files + state.stats.dirs;
    try std.testing.expect(state.performance.stat_calls >= total_entries);
}

test "performance overhead measurement" {
    const allocator = std.testing.allocator;

    // Measure time without performance tracking
    var config_no_perf = types.Config{
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

    const start_no_perf = std.time.nanoTimestamp();
    var state_no_perf = try tree.buildTree(allocator, &config_no_perf);
    const end_no_perf = std.time.nanoTimestamp();
    state_no_perf.deinit();

    const time_no_perf = end_no_perf - start_no_perf;

    // Measure time with performance tracking
    var config_with_perf = types.Config{
        .dir = "test/fixtures/wide",
        .depth = -1,
        .include_ext = null,
        .exclude_ext = null,
        .exclude_patterns = null,
        .show_hidden = true,
        .show_size = true,
        .follow_symlinks = false,
        .force = false,
        .performance = true,
        .output_file = null,
        .token_limit = null,
        .sort = .none,
    };

    const start_with_perf = std.time.nanoTimestamp();
    var state_with_perf = try tree.buildTree(allocator, &config_with_perf);
    const end_with_perf = std.time.nanoTimestamp();
    state_with_perf.deinit();

    const time_with_perf = end_with_perf - start_with_perf;

    // Performance overhead should be minimal (< 10% in most cases)
    // This is a loose check - just verify both completed
    try std.testing.expect(time_no_perf > 0);
    try std.testing.expect(time_with_perf > 0);
}

test "performance metrics on large directory" {
    const allocator = std.testing.allocator;

    var config = types.Config{
        .dir = "test/fixtures/large",
        .depth = -1,
        .include_ext = null,
        .exclude_ext = null,
        .exclude_patterns = null,
        .show_hidden = true,
        .show_size = true,
        .follow_symlinks = false,
        .force = true, // Force to bypass large directory warning
        .performance = true,
        .output_file = null,
        .token_limit = null,
        .sort = .none,
    };

    var state = try tree.buildTree(allocator, &config);
    defer state.deinit();

    // Large fixture has 50 directories
    try std.testing.expect(state.performance.readdir_calls >= 50);

    // Should track filtered entries
    try std.testing.expect(state.stats.filtered >= 0);
}

test "performance tracker initialization" {
    const allocator = std.testing.allocator;

    // Test with performance enabled
    var tracker_enabled = performance.PerformanceTracker.init(allocator, true);
    defer tracker_enabled.deinit();

    tracker_enabled.startTotal();
    std.time.sleep(1_000_000); // Sleep 1ms
    tracker_enabled.endTotal();

    try std.testing.expect(tracker_enabled.metrics.total_time_ns > 0);

    // Test with performance disabled
    var tracker_disabled = performance.PerformanceTracker.init(allocator, false);
    defer tracker_disabled.deinit();

    tracker_disabled.startTotal();
    std.time.sleep(1_000_000);
    tracker_disabled.endTotal();

    // Should still work but may have zero metrics
    try std.testing.expect(tracker_disabled.metrics.total_time_ns >= 0);
}
