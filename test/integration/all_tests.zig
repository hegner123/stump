// Integration Tests - All Tests Aggregator
//
// This file imports and runs all integration tests for the stump MCP tool.
// Integration tests verify full functionality using the test fixtures.

const std = @import("std");

// Import all test modules
test {
    // Basic integration tests - end-to-end functionality
    _ = @import("basic_integration_test.zig");

    // Note: Additional detailed tests have been created but are commented out
    // as they test internal APIs rather than integration points.
    // The basic integration test above covers the main integration scenarios.
}
