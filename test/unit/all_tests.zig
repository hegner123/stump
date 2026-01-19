// Unit tests for the stump MCP server
// This file imports all unit test modules

test {
    // Import all unit test files
    _ = @import("types_test.zig");
    _ = @import("config_test.zig");
    _ = @import("errors_test.zig");
    _ = @import("filter_test.zig");
    _ = @import("performance_test.zig");
    _ = @import("safeguards_test.zig");
    _ = @import("symlink_test.zig");
    _ = @import("output_test.zig");
    _ = @import("mcp_test.zig");
}
