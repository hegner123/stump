const std = @import("std");
const types = @import("types.zig");

/// High-resolution timer for measuring execution phases
pub const Timer = struct {
    start_time: i128,

    pub fn start() Timer {
        return Timer{
            .start_time = std.time.nanoTimestamp(),
        };
    }

    /// Returns elapsed time in milliseconds
    pub fn elapsedMs(self: *const Timer) u64 {
        const end_time = std.time.nanoTimestamp();
        const elapsed_ns = end_time - self.start_time;
        return @intCast(@divFloor(elapsed_ns, 1_000_000));
    }

    /// Returns elapsed time in microseconds
    pub fn elapsedUs(self: *const Timer) u64 {
        const end_time = std.time.nanoTimestamp();
        const elapsed_ns = end_time - self.start_time;
        return @intCast(@divFloor(elapsed_ns, 1_000));
    }

    /// Returns elapsed time in nanoseconds
    pub fn elapsedNs(self: *const Timer) u64 {
        const end_time = std.time.nanoTimestamp();
        const elapsed_ns = end_time - self.start_time;
        return @intCast(elapsed_ns);
    }
};

/// Performance tracker for monitoring resource usage throughout traversal
pub const PerformanceTracker = struct {
    allocator: std.mem.Allocator,
    enabled: bool,

    // Phase timers
    total_timer: ?Timer = null,
    traversal_timer: ?Timer = null,
    filtering_timer: ?Timer = null,
    serialization_timer: ?Timer = null,

    // Accumulated phase times (for phases that may run multiple times)
    traversal_time_ns: u64 = 0,
    filtering_time_ns: u64 = 0,
    serialization_time_ns: u64 = 0,

    // Memory tracking
    peak_memory: u64 = 0,
    allocation_count: u64 = 0,

    // Filesystem operation counters
    stat_calls: u64 = 0,
    readdir_calls: u64 = 0,
    symlink_resolutions: u64 = 0,

    // Processing counters
    items_processed: u64 = 0,
    output_bytes: u64 = 0,

    pub fn init(allocator: std.mem.Allocator, enabled: bool) PerformanceTracker {
        return PerformanceTracker{
            .allocator = allocator,
            .enabled = enabled,
        };
    }

    /// Start the total execution timer
    pub fn startTotal(self: *PerformanceTracker) void {
        if (!self.enabled) return;
        self.total_timer = Timer.start();
    }

    /// Start the traversal phase timer
    pub fn startTraversal(self: *PerformanceTracker) void {
        if (!self.enabled) return;
        self.traversal_timer = Timer.start();
    }

    /// Stop the traversal phase timer and accumulate time
    pub fn stopTraversal(self: *PerformanceTracker) void {
        if (!self.enabled) return;
        if (self.traversal_timer) |timer| {
            self.traversal_time_ns += timer.elapsedNs();
            self.traversal_timer = null;
        }
    }

    /// Start the filtering phase timer
    pub fn startFiltering(self: *PerformanceTracker) void {
        if (!self.enabled) return;
        self.filtering_timer = Timer.start();
    }

    /// Stop the filtering phase timer and accumulate time
    pub fn stopFiltering(self: *PerformanceTracker) void {
        if (!self.enabled) return;
        if (self.filtering_timer) |timer| {
            self.filtering_time_ns += timer.elapsedNs();
            self.filtering_timer = null;
        }
    }

    /// Start the serialization phase timer
    pub fn startSerialization(self: *PerformanceTracker) void {
        if (!self.enabled) return;
        self.serialization_timer = Timer.start();
    }

    /// Stop the serialization phase timer and accumulate time
    pub fn stopSerialization(self: *PerformanceTracker) void {
        if (!self.enabled) return;
        if (self.serialization_timer) |timer| {
            self.serialization_time_ns += timer.elapsedNs();
            self.serialization_timer = null;
        }
    }

    /// Record a stat() system call
    pub fn recordStatCall(self: *PerformanceTracker) void {
        if (!self.enabled) return;
        self.stat_calls += 1;
    }

    /// Record a readdir() system call
    pub fn recordReaddirCall(self: *PerformanceTracker) void {
        if (!self.enabled) return;
        self.readdir_calls += 1;
    }

    /// Record a readlink() system call (symlink resolution)
    pub fn recordSymlinkResolution(self: *PerformanceTracker) void {
        if (!self.enabled) return;
        self.symlink_resolutions += 1;
    }

    /// Record memory allocation
    pub fn recordAllocation(self: *PerformanceTracker, bytes: u64) void {
        if (!self.enabled) return;
        self.allocation_count += 1;
        if (bytes > self.peak_memory) {
            self.peak_memory = bytes;
        }
    }

    /// Update peak memory if current usage is higher
    pub fn updatePeakMemory(self: *PerformanceTracker, current_bytes: u64) void {
        if (!self.enabled) return;
        if (current_bytes > self.peak_memory) {
            self.peak_memory = current_bytes;
        }
    }

    /// Record an item being processed (file or directory)
    pub fn recordItemProcessed(self: *PerformanceTracker) void {
        if (!self.enabled) return;
        self.items_processed += 1;
    }

    /// Record output bytes generated
    pub fn recordOutputBytes(self: *PerformanceTracker, bytes: u64) void {
        if (!self.enabled) return;
        self.output_bytes += bytes;
    }

    /// Calculate and return final performance metrics
    pub fn finalize(self: *const PerformanceTracker, items_filtered: u64, final_memory_bytes: u64) types.PerformanceMetrics {
        if (!self.enabled) {
            return types.PerformanceMetrics{};
        }

        const total_ms = if (self.total_timer) |timer| timer.elapsedMs() else 0;
        const traversal_ms = self.traversal_time_ns / 1_000_000;
        const filtering_ms = self.filtering_time_ns / 1_000_000;
        const serialization_ms = self.serialization_time_ns / 1_000_000;

        // Calculate processing metrics
        const items_per_second = if (total_ms > 0)
            @divFloor(self.items_processed * 1000, total_ms)
        else
            0;

        const bytes_per_second = if (total_ms > 0)
            @divFloor(self.output_bytes * 1000, total_ms)
        else
            0;

        const avg_time_per_item_us = if (self.items_processed > 0)
            @divFloor(self.traversal_time_ns / 1000, self.items_processed)
        else
            0;

        // Calculate filter efficiency
        const total_items = self.items_processed + items_filtered;
        const filter_efficiency = if (total_items > 0)
            @as(f64, @floatFromInt(items_filtered)) / @as(f64, @floatFromInt(total_items)) * 100.0
        else
            0.0;

        return types.PerformanceMetrics{
            .total_ms = total_ms,
            .traversal_ms = traversal_ms,
            .filtering_ms = filtering_ms,
            .serialization_ms = serialization_ms,
            .peak_memory_bytes = self.peak_memory,
            .final_memory_bytes = final_memory_bytes,
            .allocations = self.allocation_count,
            .stat_calls = self.stat_calls,
            .readdir_calls = self.readdir_calls,
            .symlink_resolutions = self.symlink_resolutions,
            .items_per_second = items_per_second,
            .bytes_per_second = bytes_per_second,
            .avg_time_per_item_us = avg_time_per_item_us,
            .filter_efficiency = filter_efficiency,
            .cache_hits = 0, // Reserved for future caching implementation
        };
    }
};

/// Custom allocator wrapper for tracking memory allocations
/// This allows minimal-overhead memory tracking when performance monitoring is enabled
pub const TrackingAllocator = struct {
    parent_allocator: std.mem.Allocator,
    tracker: *PerformanceTracker,
    current_allocated: u64 = 0,

    pub fn allocator(self: *TrackingAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *TrackingAllocator = @ptrCast(@alignCast(ctx));
        const result = self.parent_allocator.rawAlloc(len, ptr_align, ret_addr);

        if (result) |ptr| {
            self.current_allocated += len;
            self.tracker.recordAllocation(len);
            self.tracker.updatePeakMemory(self.current_allocated);
            return ptr;
        }

        return null;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *TrackingAllocator = @ptrCast(@alignCast(ctx));
        const result = self.parent_allocator.rawResize(buf, buf_align, new_len, ret_addr);

        if (result) {
            if (new_len > buf.len) {
                const additional = new_len - buf.len;
                self.current_allocated += additional;
                self.tracker.updatePeakMemory(self.current_allocated);
            } else {
                const freed = buf.len - new_len;
                self.current_allocated -= freed;
            }
        }

        return result;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        const self: *TrackingAllocator = @ptrCast(@alignCast(ctx));
        self.current_allocated -= buf.len;
        self.parent_allocator.rawFree(buf, buf_align, ret_addr);
    }

    pub fn getCurrentAllocated(self: *const TrackingAllocator) u64 {
        return self.current_allocated;
    }
};

/// Helper to create a tracking allocator if performance monitoring is enabled
pub fn createTrackingAllocator(
    parent_allocator: std.mem.Allocator,
    tracker: *PerformanceTracker,
) TrackingAllocator {
    return TrackingAllocator{
        .parent_allocator = parent_allocator,
        .tracker = tracker,
    };
}
