const std = @import("std");
const testing = std.testing;
const performance = @import("stump").performance;

/// Helper function to sleep for a given number of nanoseconds
fn sleep(nanoseconds: u64) void {
    std.Thread.sleep(nanoseconds);
}

test "Timer.start creates timer with current timestamp" {
    const timer = performance.Timer.start();
    try testing.expect(timer.start_time > 0);
}

test "Timer.elapsedMs measures time in milliseconds" {
    const timer = performance.Timer.start();
    sleep(2 * std.time.ns_per_ms); // Sleep 2ms
    const elapsed = timer.elapsedMs();
    // Should be at least 1ms (accounting for timing precision)
    try testing.expect(elapsed >= 1);
}

test "Timer.elapsedUs measures time in microseconds" {
    const timer = performance.Timer.start();
    sleep(1 * std.time.ns_per_ms); // Sleep 1ms = 1000us
    const elapsed = timer.elapsedUs();
    // Should be at least 500us
    try testing.expect(elapsed >= 500);
}

test "Timer.elapsedNs measures time in nanoseconds" {
    const timer = performance.Timer.start();
    sleep(1 * std.time.ns_per_ms);
    const elapsed = timer.elapsedNs();
    // Should be at least 500,000ns
    try testing.expect(elapsed >= 500_000);
}

test "PerformanceTracker.init creates tracker with correct enabled state" {
    const allocator = testing.allocator;

    const enabled_tracker = performance.PerformanceTracker.init(allocator, true);
    try testing.expect(enabled_tracker.enabled);

    const disabled_tracker = performance.PerformanceTracker.init(allocator, false);
    try testing.expect(!disabled_tracker.enabled);
}

test "PerformanceTracker disabled tracker is a no-op" {
    const allocator = testing.allocator;
    var tracker = performance.PerformanceTracker.init(allocator, false);

    tracker.startTotal();
    tracker.startTraversal();
    tracker.stopTraversal();

    // Should remain null when disabled
    try testing.expect(tracker.total_timer == null);
    try testing.expectEqual(@as(u64, 0), tracker.traversal_time_ns);
}

test "PerformanceTracker accumulates traversal time" {
    const allocator = testing.allocator;
    var tracker = performance.PerformanceTracker.init(allocator, true);

    tracker.startTraversal();
    sleep(1 * std.time.ns_per_ms);
    tracker.stopTraversal();

    try testing.expect(tracker.traversal_time_ns > 0);

    // Accumulate more time
    const first_time = tracker.traversal_time_ns;
    tracker.startTraversal();
    sleep(1 * std.time.ns_per_ms);
    tracker.stopTraversal();

    try testing.expect(tracker.traversal_time_ns > first_time);
}

test "PerformanceTracker accumulates filtering time" {
    const allocator = testing.allocator;
    var tracker = performance.PerformanceTracker.init(allocator, true);

    tracker.startFiltering();
    sleep(1 * std.time.ns_per_ms);
    tracker.stopFiltering();

    try testing.expect(tracker.filtering_time_ns > 0);
}

test "PerformanceTracker accumulates serialization time" {
    const allocator = testing.allocator;
    var tracker = performance.PerformanceTracker.init(allocator, true);

    tracker.startSerialization();
    sleep(1 * std.time.ns_per_ms);
    tracker.stopSerialization();

    try testing.expect(tracker.serialization_time_ns > 0);
}

test "PerformanceTracker records filesystem operation counts" {
    const allocator = testing.allocator;
    var tracker = performance.PerformanceTracker.init(allocator, true);

    tracker.recordStatCall();
    tracker.recordStatCall();
    tracker.recordReaddirCall();
    tracker.recordSymlinkResolution();

    try testing.expectEqual(@as(u64, 2), tracker.stat_calls);
    try testing.expectEqual(@as(u64, 1), tracker.readdir_calls);
    try testing.expectEqual(@as(u64, 1), tracker.symlink_resolutions);
}

test "PerformanceTracker tracks items processed" {
    const allocator = testing.allocator;
    var tracker = performance.PerformanceTracker.init(allocator, true);

    tracker.recordItemProcessed();
    tracker.recordItemProcessed();
    tracker.recordItemProcessed();

    try testing.expectEqual(@as(u64, 3), tracker.items_processed);
}

test "PerformanceTracker tracks output bytes" {
    const allocator = testing.allocator;
    var tracker = performance.PerformanceTracker.init(allocator, true);

    tracker.recordOutputBytes(1024);
    tracker.recordOutputBytes(512);

    try testing.expectEqual(@as(u64, 1536), tracker.output_bytes);
}

test "PerformanceTracker initializes with zero counters" {
    const allocator = testing.allocator;
    const tracker = performance.PerformanceTracker.init(allocator, true);

    try testing.expectEqual(@as(u64, 0), tracker.traversal_time_ns);
    try testing.expectEqual(@as(u64, 0), tracker.filtering_time_ns);
    try testing.expectEqual(@as(u64, 0), tracker.serialization_time_ns);
    try testing.expectEqual(@as(u64, 0), tracker.stat_calls);
    try testing.expectEqual(@as(u64, 0), tracker.readdir_calls);
    try testing.expectEqual(@as(u64, 0), tracker.symlink_resolutions);
    try testing.expectEqual(@as(u64, 0), tracker.items_processed);
    try testing.expectEqual(@as(u64, 0), tracker.output_bytes);
}
