const std = @import("std");
const types = @import("types.zig");
const config_module = @import("config.zig");
const tree = @import("tree.zig");
const output = @import("output.zig");
const errors = @import("errors.zig");
const performance = @import("performance.zig");

// Include all module tests
test {
    @import("std").testing.refAllDecls(@This());
    _ = types;
    _ = config_module;
    _ = errors;
    _ = output;
    _ = performance;
    _ = @import("filter.zig");
    _ = @import("safeguards.zig");
    _ = @import("symlink.zig");
    _ = tree;
}

/// MCP protocol request/response structures
const McpRequest = struct {
    method: []const u8,
    params: McpParams,
};

const McpParams = struct {
    name: []const u8,
    arguments: std.json.Value,
};

const McpResponse = struct {
    result: std.json.Value,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read from stdin (MCP stdio protocol)
    const stdin = std.fs.File{ .handle = std.posix.STDIN_FILENO };
    const stdout = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    const stderr = std.fs.File{ .handle = std.posix.STDERR_FILENO };

    // Read entire input
    const input = try stdin.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB max
    defer allocator.free(input);

    // Parse JSON request
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, input, .{});
    defer parsed.deinit();

    // Process the request and generate response
    const response_json = processRequest(allocator, parsed.value) catch |err| {
        // Log error to stderr for debugging
        var stderr_buffer: [1024]u8 = undefined;
        const msg = std.fmt.bufPrint(&stderr_buffer, "Error processing request: {}\n", .{err}) catch "Error\n";
        _ = stderr.write(msg) catch {};
        return err;
    };
    defer allocator.free(response_json);

    // Write response to stdout
    _ = try stdout.write(response_json);
}

/// Process an MCP request and return JSON response
fn processRequest(allocator: std.mem.Allocator, request_value: std.json.Value) ![]u8 {
    // Extract arguments from request
    const arguments = if (request_value.object.get("params")) |params|
        if (params.object.get("arguments")) |args| args else return error.InvalidRequest
    else
        return error.InvalidRequest;

    // Parse configuration from arguments
    var config = try parseConfig(allocator, arguments);
    defer config.deinit(allocator);

    // Initialize performance tracker
    var perf_tracker = performance.PerformanceTracker.init(allocator, config.performance);
    perf_tracker.startTotal();

    // Execute the main algorithm
    const result_json = try executeStump(allocator, &config, &perf_tracker);

    return result_json;
}

/// Parse configuration from MCP arguments
fn parseConfig(allocator: std.mem.Allocator, args: std.json.Value) !types.Config {
    // Extract required 'dir' parameter
    const dir_value = args.object.get("dir") orelse return error.MissingDirectory;
    const dir_str = dir_value.string;
    const dir = try allocator.dupe(u8, dir_str);
    errdefer allocator.free(dir);

    // Extract optional parameters with defaults
    var config = types.Config{
        .dir = dir,
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

    // Parse depth
    if (args.object.get("depth")) |depth_value| {
        config.depth = @intCast(depth_value.integer);
    }

    // Parse include_ext
    if (args.object.get("include_ext")) |ext_value| {
        const ext_array = ext_value.array;
        var ext_list = try allocator.alloc([]const u8, ext_array.items.len);
        errdefer allocator.free(ext_list);

        for (ext_array.items, 0..) |item, i| {
            ext_list[i] = try allocator.dupe(u8, item.string);
        }
        config.include_ext = ext_list;
    }

    // Parse exclude_ext
    if (args.object.get("exclude_ext")) |ext_value| {
        const ext_array = ext_value.array;
        var ext_list = try allocator.alloc([]const u8, ext_array.items.len);
        errdefer allocator.free(ext_list);

        for (ext_array.items, 0..) |item, i| {
            ext_list[i] = try allocator.dupe(u8, item.string);
        }
        config.exclude_ext = ext_list;
    }

    // Parse exclude_patterns
    if (args.object.get("exclude_patterns")) |pattern_value| {
        const pattern_array = pattern_value.array;
        var pattern_list = try allocator.alloc([]const u8, pattern_array.items.len);
        errdefer allocator.free(pattern_list);

        for (pattern_array.items, 0..) |item, i| {
            pattern_list[i] = try allocator.dupe(u8, item.string);
        }
        config.exclude_patterns = pattern_list;
    }

    // Parse boolean flags
    if (args.object.get("show_hidden")) |v| {
        config.show_hidden = v.bool;
    }
    if (args.object.get("show_size")) |v| {
        config.show_size = v.bool;
    }
    if (args.object.get("follow_symlinks")) |v| {
        config.follow_symlinks = v.bool;
    }
    if (args.object.get("force")) |v| {
        config.force = v.bool;
    }
    if (args.object.get("performance")) |v| {
        config.performance = v.bool;
    }

    // Parse output_file
    if (args.object.get("output_file")) |file_value| {
        config.output_file = try allocator.dupe(u8, file_value.string);
    }

    // Parse token_limit
    if (args.object.get("token_limit")) |limit_value| {
        config.token_limit = @intCast(limit_value.integer);
    }

    // Resolve token limit (parameter > env var > default, then clamp)
    const resolved_limit = config_module.resolveTokenLimit(if (config.token_limit) |tl| @intCast(tl) else null);
    config.resolved_token_limit = resolved_limit;
    config.resolved_byte_limit = config_module.tokenLimitToBytes(resolved_limit);

    return config;
}

/// Main algorithm execution following PLAN.md steps 1-11
fn executeStump(
    allocator: std.mem.Allocator,
    config: *types.Config,
    perf_tracker: *performance.PerformanceTracker,
) ![]u8 {
    // Step 1: Input validation (already done in parseConfig)

    // Step 2: Performance tracking initialized (already done)

    // Step 3: Large directory check happens in tree.buildTree
    // Step 4: Token limit already resolved in parseConfig
    // Step 5: State initialization happens in tree.buildTree

    // Step 6: Initialize output mode
    // If output_file is set, we'll use file mode (no token limit)
    // Otherwise, stdout mode with token limit enforcement

    // Step 7-9: Build tree (traversal, filtering, collection)
    perf_tracker.startTraversal();
    var state = tree.buildTree(allocator, config) catch |err| {
        perf_tracker.stopTraversal();

        // Handle large directory fatal error
        if (err == error.LargeDirectory) {
            const fatal_error = try errors.buildLargeDirectoryError(allocator, config.dir);
            defer {
                allocator.free(fatal_error.error_name);
                allocator.free(fatal_error.path);
                allocator.free(fatal_error.message);
            }
            return try output.serializeFatalError(allocator, &fatal_error);
        }

        return err;
    };
    defer state.deinit();
    perf_tracker.stopTraversal();

    // Copy performance metrics from state to tracker
    if (config.performance) {
        perf_tracker.stat_calls = state.performance.stat_calls;
        perf_tracker.readdir_calls = state.performance.readdir_calls;
        perf_tracker.symlink_resolutions = state.performance.symlink_resolutions;
    }

    // Step 10: Build output data
    const output_data = try buildOutputData(allocator, config, &state, perf_tracker);
    defer {
        // Note: We can't call output_data.deinit() here because we're transferring
        // ownership of some fields to the serialization functions
        // The serialization functions will handle cleanup
    }

    // Step 11: Serialize and output
    if (config.output_file != null) {
        // File mode: serialize to file
        const file_success = try output.serializeToFile(allocator, &output_data, config.output_file, perf_tracker);
        defer allocator.free(file_success.message);

        // Serialize file success response as JSON
        return try serializeFileSuccess(allocator, &file_success);
    } else {
        // Stdout mode: serialize to stdout with token limit check
        // First serialize to check size
        const json_output = try output.serializeToStdout(allocator, &output_data, perf_tracker);
        errdefer allocator.free(json_output);

        if (json_output.len > config.resolved_byte_limit) {
            // Token limit exceeded - free the output and return error
            allocator.free(json_output);
            const token_limit_error = try output.serializeTokenLimitError(
                allocator,
                &state.stats,
                json_output.len,
                config.resolved_token_limit,
            );
            return token_limit_error;
        }

        // Within limit - return the JSON
        return json_output;
    }
}

/// Build OutputData from traversal state
fn buildOutputData(
    allocator: std.mem.Allocator,
    config: *const types.Config,
    state: *types.TraversalState,
    perf_tracker: *performance.PerformanceTracker,
) !types.OutputData {
    // Create OutputData
    var output_data = types.OutputData{
        .root = try allocator.dupe(u8, config.dir),
        .depth = config.depth,
        .stats = state.stats,
        .tree = state.tree_entries.items,
        .symlinks_detected = null,
        .errors = null,
        .performance = null,
        ._note = null,
    };

    // Add symlinks if detected and not following
    if (!config.follow_symlinks and state.symlinks.items.len > 0) {
        output_data.symlinks_detected = state.symlinks.items;
    }

    // Add errors if any occurred
    if (state.errors.items.len > 0) {
        output_data.errors = state.errors.items;
    }

    // Finalize and add performance metrics if requested
    if (config.performance) {
        const items_filtered = state.stats.filtered;
        const final_memory = 0; // We don't track this in the simple implementation
        output_data.performance = perf_tracker.finalize(items_filtered, final_memory);
    }

    // Add force note if force flag was used
    if (config.force) {
        output_data._note = try allocator.dupe(u8, "You asked for this");
    }

    return output_data;
}

/// Serialize FileOutputSuccess to JSON
fn serializeFileSuccess(allocator: std.mem.Allocator, success: *const types.FileOutputSuccess) ![]u8 {
    var buffer = std.ArrayList(u8){};
    errdefer buffer.deinit(allocator);

    var writer = buffer.writer(allocator);

    try writer.writeAll("{\"success\":true,\"message\":\"");
    try writer.writeAll(success.message);
    try writer.writeAll("\",\"stats\":{");

    try writer.print("\"dirs\":{},\"files\":{}", .{ success.stats.dirs, success.stats.files });

    if (success.stats.filtered > 0) {
        try writer.print(",\"filtered\":{}", .{success.stats.filtered});
    }
    if (success.stats.symlinks > 0) {
        try writer.print(",\"symlinks\":{}", .{success.stats.symlinks});
    }

    try writer.writeAll("}}");

    return try buffer.toOwnedSlice(allocator);
}
