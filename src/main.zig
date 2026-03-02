/// Stump entrypoint: dual-mode CLI and MCP server for directory tree visualization.
///
/// Detects the execution mode at startup: if CLI arguments are present, runs as
/// a one-shot CLI tool that prints the tree to stdout/file and exits. Otherwise,
/// enters the MCP stdio protocol loop, reading JSON-RPC 2.0 requests from stdin
/// and writing responses to stdout. Both modes share the same core pipeline:
/// config parsing -> tree.buildTree -> output serialization.
const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const config_module = @import("config.zig");
const tree = @import("tree.zig");
const output = @import("output.zig");
const errors = @import("errors.zig");
const performance = @import("performance.zig");
const mcp = @import("mcp.zig");

const JsonRpcError = mcp.JsonRpcError;
const buildErrorResponse = mcp.buildErrorResponse;
const buildSuccessResponse = mcp.buildSuccessResponse;
const buildToolContent = mcp.buildToolContent;

/// Parsed CLI arguments bundling a Config with the help-flag state.
///
/// Produced by parseCliArgs, consumed by runCliMode. Owns the Config
/// and must be freed via deinit.
const CliArgs = struct {
    config: types.Config,
    show_help: bool = false,

    pub fn deinit(self: *CliArgs, allocator: std.mem.Allocator) void {
        self.config.deinit(allocator);
    }
};

/// CLI parsing errors
const CliError = error{
    MissingDirectory,
    InvalidDepth,
    InvalidTokenLimit,
    UnknownFlag,
    MissingValue,
    OutOfMemory,
};

/// Print CLI help message
fn printHelp(file: std.fs.File) !void {
    const help_text =
        \\stump - Token-efficient directory tree visualization
        \\
        \\USAGE:
        \\  stump [OPTIONS] <directory>
        \\  stump                        (runs as MCP server via stdio)
        \\
        \\ARGUMENTS:
        \\  <directory>                  Root directory to scan
        \\
        \\OPTIONS:
        \\  -h, --help                   Show this help message
        \\  -d, --depth <N>              Max traversal depth (-1 for unlimited, default: -1)
        \\  -o, --output <file>          Output to file instead of stdout
        \\  --include-ext <ext,...>      Only include files with these extensions
        \\  --exclude-ext <ext,...>      Exclude files with these extensions
        \\  --exclude <pattern,...>      Exclude paths matching patterns
        \\  --hidden                     Show hidden files (default: true)
        \\  --no-hidden                  Hide hidden files
        \\  --size                       Show file sizes (default: true)
        \\  --no-size                    Hide file sizes
        \\  --modified                   Show modification timestamps
        \\  --no-modified                Hide modification timestamps (default)
        \\  --follow-symlinks            Follow symbolic links
        \\  --force                      Bypass large directory safeguards
        \\  --performance                Include performance metrics
        \\  --token-limit <N>            Token limit (1000-100000, default: 10000)
        \\
        \\EXAMPLES:
        \\  stump .                      Scan current directory
        \\  stump ~/projects -d 3        Scan with max depth 3
        \\  stump src --exclude-ext log,tmp
        \\  stump . --no-hidden -o tree.json
        \\
        \\ENVIRONMENT:
        \\  STUMP_TOKEN_LIMIT            Default token limit (overridden by --token-limit)
        \\
    ;
    _ = try file.write(help_text);
}

/// Split a comma-separated string into array
fn splitCommaList(allocator: std.mem.Allocator, input: []const u8) ![]const []const u8 {
    var count: usize = 1;
    for (input) |c| {
        if (c == ',') count += 1;
    }

    var list = try allocator.alloc([]const u8, count);
    errdefer allocator.free(list);

    var allocated: usize = 0;
    errdefer {
        for (list[0..allocated]) |item| {
            allocator.free(item);
        }
    }

    var start: usize = 0;
    var idx: usize = 0;
    for (input, 0..) |c, i| {
        if (c == ',') {
            list[idx] = try allocator.dupe(u8, input[start..i]);
            allocated += 1;
            idx += 1;
            start = i + 1;
        }
    }
    list[idx] = try allocator.dupe(u8, input[start..]);
    allocated += 1;

    return list;
}

/// Parse CLI arguments into config
fn parseCliArgs(allocator: std.mem.Allocator) CliError!CliArgs {
    var args_iter = std.process.args();
    _ = args_iter.skip(); // Skip program name

    var result = CliArgs{
        .config = types.Config{
            .dir = undefined,
            .depth = -1,
            .include_ext = null,
            .exclude_ext = null,
            .exclude_patterns = null,
            .show_hidden = true,
            .show_size = true,
            .show_modified = false,
            .follow_symlinks = false,
            .force = false,
            .performance = false,
            .output_file = null,
            .token_limit = null,
            .sort = .none,
        },
        .show_help = false,
    };

    var dir_set = false;

    while (args_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            result.show_help = true;
            result.config.dir = allocator.dupe(u8, ".") catch return CliError.OutOfMemory;
            return result;
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--depth")) {
            const val = args_iter.next() orelse return CliError.MissingValue;
            result.config.depth = std.fmt.parseInt(i32, val, 10) catch return CliError.InvalidDepth;
        } else if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
            const val = args_iter.next() orelse return CliError.MissingValue;
            result.config.output_file = allocator.dupe(u8, val) catch return CliError.OutOfMemory;
        } else if (std.mem.eql(u8, arg, "--include-ext")) {
            const val = args_iter.next() orelse return CliError.MissingValue;
            result.config.include_ext = splitCommaList(allocator, val) catch return CliError.OutOfMemory;
        } else if (std.mem.eql(u8, arg, "--exclude-ext")) {
            const val = args_iter.next() orelse return CliError.MissingValue;
            result.config.exclude_ext = splitCommaList(allocator, val) catch return CliError.OutOfMemory;
        } else if (std.mem.eql(u8, arg, "--exclude")) {
            const val = args_iter.next() orelse return CliError.MissingValue;
            result.config.exclude_patterns = splitCommaList(allocator, val) catch return CliError.OutOfMemory;
        } else if (std.mem.eql(u8, arg, "--hidden")) {
            result.config.show_hidden = true;
        } else if (std.mem.eql(u8, arg, "--no-hidden")) {
            result.config.show_hidden = false;
        } else if (std.mem.eql(u8, arg, "--size")) {
            result.config.show_size = true;
        } else if (std.mem.eql(u8, arg, "--no-size")) {
            result.config.show_size = false;
        } else if (std.mem.eql(u8, arg, "--modified")) {
            result.config.show_modified = true;
        } else if (std.mem.eql(u8, arg, "--no-modified")) {
            result.config.show_modified = false;
        } else if (std.mem.eql(u8, arg, "--follow-symlinks")) {
            result.config.follow_symlinks = true;
        } else if (std.mem.eql(u8, arg, "--force")) {
            result.config.force = true;
        } else if (std.mem.eql(u8, arg, "--performance")) {
            result.config.performance = true;
        } else if (std.mem.eql(u8, arg, "--token-limit")) {
            const val = args_iter.next() orelse return CliError.MissingValue;
            result.config.token_limit = std.fmt.parseInt(u64, val, 10) catch return CliError.InvalidTokenLimit;
        } else if (arg[0] == '-') {
            return CliError.UnknownFlag;
        } else {
            // Positional argument - directory
            if (!dir_set) {
                result.config.dir = allocator.dupe(u8, arg) catch return CliError.OutOfMemory;
                dir_set = true;
            }
        }
    }

    if (!dir_set) {
        return CliError.MissingDirectory;
    }

    // Resolve token limit
    const resolved_limit = config_module.resolveTokenLimit(if (result.config.token_limit) |tl| @intCast(tl) else null);
    result.config.resolved_token_limit = resolved_limit;
    result.config.resolved_byte_limit = config_module.tokenLimitToBytes(resolved_limit);

    return result;
}

/// CLI execution path: parses arguments, runs the tree pipeline, writes output.
///
/// Called from main when hasCliArgs returns true. Handles help display, error
/// reporting to stderr, and exit code selection (0 success, 1 error).
fn runCliMode(allocator: std.mem.Allocator) !u8 {
    const stderr_file = std.fs.File.stderr();
    const stdout_file = std.fs.File.stdout();

    var cli_args = parseCliArgs(allocator) catch |err| {
        const msg: []const u8 = switch (err) {
            CliError.MissingDirectory => "Error: missing directory argument\nRun 'stump --help' for usage\n",
            CliError.InvalidDepth => "Error: invalid depth value\n",
            CliError.InvalidTokenLimit => "Error: invalid token-limit value\n",
            CliError.UnknownFlag => "Error: unknown flag\nRun 'stump --help' for usage\n",
            CliError.MissingValue => "Error: missing value for flag\n",
            CliError.OutOfMemory => "Error: out of memory\n",
        };
        _ = stderr_file.write(msg) catch {};
        return 1;
    };
    defer cli_args.deinit(allocator);

    if (cli_args.show_help) {
        printHelp(stdout_file) catch {};
        return 0;
    }

    // Initialize performance tracker
    var perf_tracker = performance.PerformanceTracker.init(allocator, cli_args.config.performance);
    perf_tracker.startTotal();

    // Execute the main algorithm
    const result = executeStump(allocator, &cli_args.config, &perf_tracker) catch |err| {
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "Error: {}\n", .{err}) catch "Error\n";
        _ = stderr_file.write(msg) catch {};
        return 1;
    };
    defer allocator.free(result.json);

    // Output result
    _ = try stdout_file.write(result.json);
    _ = try stdout_file.write("\n");

    return if (result.is_error) 1 else 0;
}

/// Check if stdin is a terminal (interactive) or piped
fn isStdinTerminal() bool {
    return std.fs.File.stdin().isTty();
}

/// Check if any CLI arguments were passed
fn hasCliArgs() bool {
    var args = std.process.args();
    _ = args.skip(); // Skip program name
    return args.next() != null;
}

/// Pairing of serialized JSON output with an error flag, returned by executeStump.
///
/// When is_error is true, the json field contains a fatal error or token-limit
/// error payload. In MCP mode, handleToolsCall uses is_error to set the MCP
/// isError flag on the tool content wrapper.
const StumpResult = struct {
    json: []u8,
    is_error: bool,
};

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

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Detect mode: CLI if arguments passed, otherwise MCP
    if (hasCliArgs()) {
        return runCliMode(allocator);
    }

    // MCP stdio protocol - read line by line
    const stdin = std.fs.File.stdin();
    const stdout = std.fs.File.stdout();

    // Create buffered reader/writer for stdin/stdout
    var reader_buffer: [64 * 1024]u8 = undefined; // 64KB buffer
    var reader = stdin.readerStreaming(&reader_buffer);

    // Protocol state machine
    var protocol_state = mcp.ProtocolState.uninitialized;

    // Cancellation tracker for notifications/cancelled
    var cancellation_tracker = mcp.CancellationTracker.init(allocator);
    defer cancellation_tracker.deinit();

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
        var parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch {
            // JSON parse error - return error response with null id
            const error_response = buildErrorResponse(
                allocator,
                null,
                JsonRpcError.PARSE_ERROR,
                "Parse error: invalid JSON",
            ) catch continue;
            defer allocator.free(error_response);
            _ = stdout.write(error_response) catch {};
            _ = stdout.write("\n") catch {};
            continue;
        };
        defer parsed.deinit();

        // Extract id for error responses (may be null for notifications)
        const request_id = parsed.value.object.get("id");

        // Validate jsonrpc version field
        if (parsed.value.object.get("jsonrpc")) |jsonrpc| {
            if (jsonrpc != .string or !std.mem.eql(u8, jsonrpc.string, "2.0")) {
                const error_response = buildErrorResponse(
                    allocator,
                    request_id,
                    JsonRpcError.INVALID_REQUEST,
                    "Invalid Request: 'jsonrpc' must be '2.0'",
                ) catch continue;
                defer allocator.free(error_response);
                _ = stdout.write(error_response) catch {};
                _ = stdout.write("\n") catch {};
                continue;
            }
        } else {
            // Missing jsonrpc field
            const error_response = buildErrorResponse(
                allocator,
                request_id,
                JsonRpcError.INVALID_REQUEST,
                "Invalid Request: missing 'jsonrpc' field",
            ) catch continue;
            defer allocator.free(error_response);
            _ = stdout.write(error_response) catch {};
            _ = stdout.write("\n") catch {};
            continue;
        }

        // Extract method for state validation
        const method = if (parsed.value.object.get("method")) |m|
            m.string
        else {
            // Missing method - send error response
            const error_response = buildErrorResponse(
                allocator,
                request_id,
                JsonRpcError.INVALID_REQUEST,
                "Invalid Request: missing 'method' field",
            ) catch continue;
            defer allocator.free(error_response);
            _ = stdout.write(error_response) catch {};
            _ = stdout.write("\n") catch {};
            continue;
        };

        // Check if this is a notification (no id, no response expected)
        const is_notification = mcp.isNotification(method);

        // Validate method is allowed in current state
        if (!protocol_state.isMethodAllowed(method)) {
            // Only send error for requests, not notifications
            if (!is_notification) {
                const error_message = switch (protocol_state) {
                    .uninitialized => "Invalid Request: must call 'initialize' first",
                    .initializing => "Invalid Request: waiting for 'initialized' notification",
                    .ready => "Invalid Request: 'initialize' already called",
                };
                const error_response = buildErrorResponse(
                    allocator,
                    request_id,
                    JsonRpcError.INVALID_REQUEST,
                    error_message,
                ) catch continue;
                defer allocator.free(error_response);
                _ = stdout.write(error_response) catch {};
                _ = stdout.write("\n") catch {};
            }
            continue;
        }

        // Handle notifications (no response)
        if (is_notification) {
            // Handle notifications/cancelled specially
            if (std.mem.eql(u8, method, "notifications/cancelled")) {
                // Extract the requestId from params and mark it as cancelled
                if (parsed.value.object.get("params")) |params| {
                    if (params.object.get("requestId")) |cancelled_id| {
                        cancellation_tracker.cancel(cancelled_id) catch {};
                    }
                }
            }
            // Update state for initialized notification
            protocol_state = protocol_state.nextState(method);
            continue;
        }

        // Check if this request was already cancelled before we process it
        if (request_id) |id| {
            if (cancellation_tracker.isCancelled(id)) {
                // Request was cancelled - remove from tracker and skip processing
                cancellation_tracker.remove(id);
                continue;
            }
        }

        // Process the request and generate response
        const response_json = processRequest(allocator, parsed.value) catch |err| {
            // Map Zig errors to JSON-RPC error codes
            const error_code: i32 = switch (err) {
                error.InvalidRequest => JsonRpcError.INVALID_REQUEST,
                error.MethodNotFound => JsonRpcError.METHOD_NOT_FOUND,
                error.InvalidParams, error.MissingDirectory => JsonRpcError.INVALID_PARAMS,
                error.ToolNotFound => JsonRpcError.TOOL_NOT_FOUND,
                else => JsonRpcError.INTERNAL_ERROR,
            };

            const error_message: []const u8 = switch (err) {
                error.InvalidRequest => "Invalid Request: missing required fields",
                error.MethodNotFound => "Method not found",
                error.InvalidParams => "Invalid params",
                error.MissingDirectory => "Invalid params: missing required 'dir' parameter",
                error.ToolNotFound => "Tool not found: only 'stump' tool is available",
                else => "Internal error",
            };

            const error_response = buildErrorResponse(
                allocator,
                request_id,
                error_code,
                error_message,
            ) catch continue;
            defer allocator.free(error_response);
            _ = stdout.write(error_response) catch {};
            _ = stdout.write("\n") catch {};
            continue;
        };
        defer allocator.free(response_json);

        // Update protocol state after successful request
        protocol_state = protocol_state.nextState(method);

        // Write response to stdout with newline
        _ = try stdout.write(response_json);
        _ = try stdout.write("\n");
    }

    return 0;
}

/// Reads one newline-delimited line from the MCP stdin stream.
///
/// Handles lines that exceed the 64KB reader buffer by accumulating chunks
/// via recursive calls (capped at 10MB to prevent OOM). Returns an owned
/// slice. Called in the main MCP request loop for each JSON-RPC message.
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

/// Routes a parsed JSON-RPC request to the appropriate MCP method handler.
///
/// Dispatches to handleInitialize, handlePing, handleToolsList, or
/// handleToolsCall based on the "method" field. Returns error.MethodNotFound
/// for unrecognized methods, which the caller maps to JSON-RPC -32601.
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
    } else if (std.mem.eql(u8, method, "ping")) {
        return handlePing(allocator, id);
    } else if (std.mem.eql(u8, method, "tools/list")) {
        return handleToolsList(allocator, id);
    } else if (std.mem.eql(u8, method, "tools/call")) {
        return handleToolsCall(allocator, request_value, id);
    } else {
        return error.MethodNotFound;
    }
}

/// Responds to the MCP "initialize" handshake with server capabilities.
///
/// Returns protocol version 2024-11-05, server name/version, and declares
/// support for tools (list, call, listChanged). Transitions ProtocolState
/// from uninitialized to initializing.
fn handleInitialize(allocator: std.mem.Allocator, id: std.json.Value) ![]u8 {
    const result =
        \\{"protocolVersion":"2024-11-05","serverInfo":{"name":"stump","version":"1.0.0"},"capabilities":{"tools":{"list":true,"call":true,"listChanged":true}}}
    ;
    return buildSuccessResponse(allocator, id, result);
}

/// Handle MCP ping request (connection health check)
fn handlePing(allocator: std.mem.Allocator, id: std.json.Value) ![]u8 {
    // Ping returns an empty result object
    return buildSuccessResponse(allocator, id, "{}");
}

/// Returns the tool catalog containing the single "stump" tool with its JSON Schema.
///
/// The schema declares "dir" as the only required parameter. All other
/// parameters (depth, include_ext, exclude_ext, etc.) are optional with
/// defaults matching Config field defaults in types.zig.
fn handleToolsList(allocator: std.mem.Allocator, id: std.json.Value) ![]u8 {
    const result =
        \\{"tools":[{"name":"stump","description":"Token-efficient directory tree visualization","inputSchema":{"type":"object","properties":{"dir":{"type":"string","description":"Root directory to scan"},"depth":{"type":"integer","description":"Max traversal depth (-1 for unlimited)"},"include_ext":{"type":"array","items":{"type":"string"}},"exclude_ext":{"type":"array","items":{"type":"string"}},"exclude_patterns":{"type":"array","items":{"type":"string"}},"show_hidden":{"type":"boolean"},"show_size":{"type":"boolean"},"show_modified":{"type":"boolean","description":"Include modification timestamps"},"follow_symlinks":{"type":"boolean"},"force":{"type":"boolean"},"performance":{"type":"boolean"},"output_file":{"type":"string"},"token_limit":{"type":"integer"}},"required":["dir"]}}]}
    ;
    return buildSuccessResponse(allocator, id, result);
}

/// Executes the "stump" tool: parses arguments, runs the tree pipeline, wraps output.
///
/// Validates that the tool name is "stump", extracts arguments from the MCP
/// params, builds a Config via parseConfig, runs executeStump, and wraps the
/// result in an MCP content array via mcp.buildToolContent. Returns
/// error.ToolNotFound for any tool name other than "stump".
fn handleToolsCall(allocator: std.mem.Allocator, request_value: std.json.Value, id: std.json.Value) ![]u8 {
    // Extract params object
    const params = request_value.object.get("params") orelse return error.InvalidParams;

    // Validate tool name
    const tool_name = if (params.object.get("name")) |name|
        name.string
    else
        return error.InvalidParams;

    if (!std.mem.eql(u8, tool_name, "stump")) {
        return error.ToolNotFound;
    }

    // Extract arguments from params
    const arguments = params.object.get("arguments") orelse return error.InvalidParams;

    // Parse configuration from arguments
    var config = try parseConfig(allocator, arguments);
    defer config.deinit(allocator);

    // Initialize performance tracker
    var perf_tracker = performance.PerformanceTracker.init(allocator, config.performance);
    perf_tracker.startTotal();

    // Execute the main algorithm
    const result = try executeStump(allocator, &config, &perf_tracker);
    defer allocator.free(result.json);

    // Build the result wrapper with isError flag if needed
    const result_wrapper = try buildToolContent(allocator, result.json, result.is_error);
    defer allocator.free(result_wrapper);

    return buildSuccessResponse(allocator, id, result_wrapper);
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

/// Transforms MCP JSON arguments into a Config struct for tree traversal.
///
/// Called by handleToolsCall. Extracts the required "dir" parameter and all
/// optional parameters, applying the same defaults as CLI mode. Resolves the
/// token limit via config_module.resolveTokenLimit (parameter > env > default).
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
        .show_modified = false,
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
    if (args.object.get("show_modified")) |v| {
        config.show_modified = v.bool;
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

/// Core execution pipeline shared by CLI and MCP modes.
///
/// Orchestrates the full sequence: tree.buildTree (traversal with filtering
/// and safeguards), buildOutputData (assembly from TraversalState), and
/// output serialization (to file or stdout with token limit enforcement).
/// Returns a StumpResult containing the serialized JSON and an error flag
/// indicating whether the output represents a tool error (large directory,
/// token limit exceeded) vs. successful tree data.
fn executeStump(
    allocator: std.mem.Allocator,
    config: *types.Config,
    perf_tracker: *performance.PerformanceTracker,
) !StumpResult {
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

        // Handle large directory fatal error - return as error content
        if (err == error.LargeDirectory) {
            var fatal_error = try errors.buildLargeDirectoryError(allocator, config.dir);
            defer fatal_error.deinit(allocator);
            return StumpResult{
                .json = try output.serializeFatalError(allocator, &fatal_error),
                .is_error = true,
            };
        }

        // Handle token limit exceeded during traversal - return as error content
        if (err == error.TokenLimitExceeded) {
            // Create a minimal stats object for the error message
            const partial_stats = types.Stats{
                .dirs = 0,
                .files = 0,
                .filtered = 0,
                .symlinks = 0,
            };
            return StumpResult{
                .json = try output.serializeTokenLimitError(
                    allocator,
                    &partial_stats,
                    config.resolved_byte_limit,
                    config.resolved_token_limit,
                ),
                .is_error = true,
            };
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
    var output_data = try buildOutputData(allocator, config, &state, perf_tracker);
    defer {
        // Free OutputData fields we own (root and _note are allocated by buildOutputData)
        // Tree entries are managed by TraversalState.deinit()
        allocator.free(output_data.root);
        if (output_data._note) |note| allocator.free(note);
    }

    // Step 11: Serialize and output
    if (config.output_file != null) {
        // File mode: serialize to file
        const file_success = try output.serializeToFile(allocator, &output_data, config.output_file, perf_tracker);
        defer allocator.free(file_success.message);

        // Serialize file success response as JSON (not an error)
        return StumpResult{
            .json = try serializeFileSuccess(allocator, &file_success),
            .is_error = false,
        };
    } else {
        // Stdout mode: serialize to stdout with token limit check
        // First serialize to check size
        const json_output = try output.serializeToStdout(allocator, &output_data, perf_tracker);
        errdefer allocator.free(json_output);

        if (json_output.len > config.resolved_byte_limit) {
            // Token limit exceeded - free the output and return error content
            allocator.free(json_output);
            return StumpResult{
                .json = try output.serializeTokenLimitError(
                    allocator,
                    &state.stats,
                    json_output.len,
                    config.resolved_token_limit,
                ),
                .is_error = true,
            };
        }

        // Within limit - return the JSON (not an error)
        return StumpResult{
            .json = json_output,
            .is_error = false,
        };
    }
}

/// Assembles the final OutputData struct from traversal results.
///
/// Borrows slice references from TraversalState (tree_entries, symlinks, errors)
/// rather than copying them. Only the root path string and the optional _note
/// are independently allocated. Called by executeStump after tree.buildTree
/// completes successfully.
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

/// Serializes the file-output success message (filename, stats) to JSON.
///
/// Called by executeStump when output_file is set and the tree was successfully
/// written to disk. The resulting JSON is either printed to stdout (CLI mode)
/// or wrapped in an MCP tool content response (MCP mode).
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
