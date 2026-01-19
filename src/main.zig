const std = @import("std");
const types = @import("types.zig");
const config_module = @import("config.zig");
const tree = @import("tree.zig");
const output = @import("output.zig");
const errors = @import("errors.zig");
const performance = @import("performance.zig");

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

    // MCP stdio protocol - read line by line
    const stdin = std.fs.File{ .handle = std.posix.STDIN_FILENO };
    const stdout = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    const stderr = std.fs.File{ .handle = std.posix.STDERR_FILENO };

    // Create buffered reader/writer for stdin/stdout
    var reader_buffer: [64 * 1024]u8 = undefined; // 64KB buffer
    var reader = stdin.readerStreaming(&reader_buffer);

    // Read and process requests line by line
    while (true) {
        // Read one line (one JSON-RPC request)
        const line = readLine(allocator, &reader) catch |err| {
            if (err == error.EndOfStream) break;
            return err;
        };
        defer allocator.free(line);

        // Skip empty lines
        if (line.len == 0) continue;

        // Parse JSON request
        var parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch |err| {
            // Log parse error to stderr
            var err_buf: [256]u8 = undefined;
            const err_msg = std.fmt.bufPrint(&err_buf, "JSON parse error: {}\n", .{err}) catch "Parse error\n";
            _ = stderr.write(err_msg) catch {};
            continue;
        };
        defer parsed.deinit();

        // Process the request and generate response
        const response_json = processRequest(allocator, parsed.value) catch |err| {
            // Log error to stderr for debugging
            var err_buf: [256]u8 = undefined;
            const err_msg = std.fmt.bufPrint(&err_buf, "Error: {}\n", .{err}) catch "Error\n";
            _ = stderr.write(err_msg) catch {};
            continue;
        };
        defer allocator.free(response_json);

        // Write response to stdout with newline
        _ = try stdout.write(response_json);
        _ = try stdout.write("\n");
    }
}

/// Read a line from the reader, allocating as needed for large lines
fn readLine(allocator: std.mem.Allocator, reader: *std.fs.File.Reader) ![]u8 {
    var line_buffer = std.ArrayList(u8){};
    errdefer line_buffer.deinit(allocator);

    // Use takeDelimiter to efficiently read until newline
    // This handles the buffering internally
    const line_slice = reader.interface.takeDelimiter('\n') catch |err| {
        if (err == error.ReadFailed) {
            // End of stream without delimiter
            const remaining = reader.interface.buffered();
            if (remaining.len == 0 and line_buffer.items.len == 0) {
                return error.EndOfStream;
            }
            // Return any buffered data
            try line_buffer.appendSlice(allocator, remaining);
            reader.interface.tossBuffered();
            return try line_buffer.toOwnedSlice(allocator);
        }
        if (err == error.StreamTooLong) {
            // Line longer than buffer - accumulate and continue
            const buffered = reader.interface.buffered();
            try line_buffer.appendSlice(allocator, buffered);
            reader.interface.tossBuffered();

            // Safety limit - 10MB max line
            if (line_buffer.items.len > 10 * 1024 * 1024) {
                return error.StreamTooLong;
            }

            // Recursively continue reading
            const rest = try readLine(allocator, reader);
            defer allocator.free(rest);
            try line_buffer.appendSlice(allocator, rest);
            return try line_buffer.toOwnedSlice(allocator);
        }
        return err;
    };

    // Got a complete line (or null for EOF with no data)
    if (line_slice) |slice| {
        // If we had accumulated data, combine it
        if (line_buffer.items.len > 0) {
            try line_buffer.appendSlice(allocator, slice);
            return try line_buffer.toOwnedSlice(allocator);
        }
        // Otherwise, copy the slice (it's from internal buffer)
        return try allocator.dupe(u8, slice);
    } else {
        // EOF with no data
        if (line_buffer.items.len == 0) {
            return error.EndOfStream;
        }
        return try line_buffer.toOwnedSlice(allocator);
    }
}

/// Process an MCP request and return JSON response
fn processRequest(allocator: std.mem.Allocator, request_value: std.json.Value) ![]u8 {
    // Extract method from request
    const method = if (request_value.object.get("method")) |m|
        m.string
    else
        return error.InvalidRequest;

    const id = if (request_value.object.get("id")) |i| i else return error.InvalidRequest;

    // Handle different MCP methods
    if (std.mem.eql(u8, method, "initialize")) {
        return handleInitialize(allocator, id);
    } else if (std.mem.eql(u8, method, "tools/list")) {
        return handleToolsList(allocator, id);
    } else if (std.mem.eql(u8, method, "tools/call")) {
        return handleToolsCall(allocator, request_value, id);
    } else {
        return error.MethodNotFound;
    }
}

/// Handle MCP initialize request
fn handleInitialize(allocator: std.mem.Allocator, id: std.json.Value) ![]u8 {
    // Handle id as integer (most common case)
    const id_int = if (id == .integer) id.integer else 1;

    const response = try std.fmt.allocPrint(allocator,
        \\{{"jsonrpc":"2.0","id":{d},"result":{{"protocolVersion":"2024-11-05","serverInfo":{{"name":"stump","version":"1.0.0"}},"capabilities":{{"tools":{{"list":true,"call":true,"listChanged":true}}}}}}}}
    , .{id_int});

    return response;
}

/// Handle MCP tools/list request
fn handleToolsList(allocator: std.mem.Allocator, id: std.json.Value) ![]u8 {
    // Handle id as integer (most common case)
    const id_int = if (id == .integer) id.integer else 1;

    const response = try std.fmt.allocPrint(allocator,
        \\{{"jsonrpc":"2.0","id":{d},"result":{{"tools":[{{"name":"stump","description":"Token-efficient directory tree visualization","inputSchema":{{"type":"object","properties":{{"dir":{{"type":"string","description":"Root directory to scan"}},"depth":{{"type":"integer","description":"Max traversal depth (-1 for unlimited)"}},"include_ext":{{"type":"array","items":{{"type":"string"}}}},"exclude_ext":{{"type":"array","items":{{"type":"string"}}}},"exclude_patterns":{{"type":"array","items":{{"type":"string"}}}},"show_hidden":{{"type":"boolean"}},"show_size":{{"type":"boolean"}},"follow_symlinks":{{"type":"boolean"}},"force":{{"type":"boolean"}},"performance":{{"type":"boolean"}},"output_file":{{"type":"string"}},"token_limit":{{"type":"integer"}}}},"required":["dir"]}}}}]}}}}
    , .{id_int});

    return response;
}

/// Handle MCP tools/call request
fn handleToolsCall(allocator: std.mem.Allocator, request_value: std.json.Value, id: std.json.Value) ![]u8 {
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
    defer allocator.free(result_json);

    // Handle id as integer (most common case)
    const id_int = if (id == .integer) id.integer else 1;

    const response = try std.fmt.allocPrint(allocator,
        \\{{"jsonrpc":"2.0","id":{d},"result":{{"content":[{{"type":"text","text":{s}}}]}}}}
    , .{ id_int, result_json });

    return response;
}

/// Helper to parse string arrays from JSON with proper cleanup on error
fn parseStringArray(allocator: std.mem.Allocator, array: std.json.Array) ![]const []const u8 {
    var list = try allocator.alloc([]const u8, array.items.len);
    errdefer allocator.free(list);

    var allocated_count: usize = 0;
    errdefer {
        // Free all successfully allocated items on error
        for (list[0..allocated_count]) |item| {
            allocator.free(item);
        }
    }

    for (array.items, 0..) |item, i| {
        list[i] = try allocator.dupe(u8, item.string);
        allocated_count += 1;
    }

    return list;
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
        config.include_ext = try parseStringArray(allocator, ext_value.array);
    }

    // Parse exclude_ext
    if (args.object.get("exclude_ext")) |ext_value| {
        config.exclude_ext = try parseStringArray(allocator, ext_value.array);
    }

    // Parse exclude_patterns
    if (args.object.get("exclude_patterns")) |pattern_value| {
        config.exclude_patterns = try parseStringArray(allocator, pattern_value.array);
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
            var fatal_error = try errors.buildLargeDirectoryError(allocator, config.dir);
            defer fatal_error.deinit(allocator);
            return try output.serializeFatalError(allocator, &fatal_error);
        }

        // Handle token limit exceeded during traversal
        if (err == error.TokenLimitExceeded) {
            // Create a minimal stats object for the error message
            const partial_stats = types.Stats{
                .dirs = 0,
                .files = 0,
                .filtered = 0,
                .symlinks = 0,
            };
            return try output.serializeTokenLimitError(
                allocator,
                &partial_stats,
                config.resolved_byte_limit,
                config.resolved_token_limit,
            );
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
