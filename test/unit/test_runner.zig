// Test runner - imports all test files
// Each test file uses comptime to get module references

comptime {
    _ = @import("types_test.zig");
    _ = @import("config_test.zig");
    _ = @import("errors_test.zig");
    _ = @import("filter_test.zig");
    _ = @import("performance_test.zig");
    _ = @import("safeguards_test.zig");
    _ = @import("symlink_test.zig");
    _ = @import("output_test.zig");
}
