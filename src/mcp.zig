/// JSON-RPC 2.0 and MCP protocol utilities for the stump MCP server.
///
/// Imported by main.zig to drive the stdio-based MCP request/response loop.
/// Provides the protocol state machine (initialize -> initialized -> ready),
/// JSON-RPC response builders, error code constants, and request cancellation
/// tracking. Contains no filesystem or tree logic -- purely protocol concerns.
const std = @import("std");

/// Tracks the MCP handshake lifecycle in main.zig's request loop.
///
/// Transitions: uninitialized -> initializing (on "initialize" request)
/// -> ready (on "initialized" notification). Methods are rejected if
/// called in the wrong state, producing JSON-RPC INVALID_REQUEST errors.
pub const ProtocolState = enum {
    /// Initial state - only initialize allowed
    uninitialized,
    /// After initialize response sent - waiting for initialized notification
    initializing,
    /// After initialized notification - all methods allowed
    ready,

    /// Check if a method is allowed in the current state
    pub fn isMethodAllowed(self: ProtocolState, method: []const u8) bool {
        return switch (self) {
            .uninitialized => std.mem.eql(u8, method, "initialize"),
            // Allow all methods after initialize — some clients (e.g. Crush)
            // skip the notifications/initialized step
            .initializing, .ready => !std.mem.eql(u8, method, "initialize"),
        };
    }

    /// Get the next state after processing a method
    pub fn nextState(self: ProtocolState, method: []const u8) ProtocolState {
        return switch (self) {
            .uninitialized => if (std.mem.eql(u8, method, "initialize")) .initializing else self,
            .initializing => .ready,
            .ready => self,
        };
    }
};

/// Identifies MCP notification methods that require no response.
///
/// Called by main.zig's request loop to decide whether to send a response
/// or silently process the message. Notifications include "initialized"
/// and any method prefixed with "notifications/" (e.g., "notifications/cancelled").
pub fn isNotification(method: []const u8) bool {
    return std.mem.eql(u8, method, "initialized") or
        std.mem.startsWith(u8, method, "notifications/");
}

/// JSON-RPC 2.0 error codes used by buildErrorResponse in main.zig's error
/// handling paths. TOOL_NOT_FOUND is an application-defined code for when
/// a tools/call request names a tool other than "stump".
pub const JsonRpcError = struct {
    // Standard JSON-RPC 2.0 errors
    pub const PARSE_ERROR: i32 = -32700;
    pub const INVALID_REQUEST: i32 = -32600;
    pub const METHOD_NOT_FOUND: i32 = -32601;
    pub const INVALID_PARAMS: i32 = -32602;
    pub const INTERNAL_ERROR: i32 = -32603;

    // Application-defined errors (-32000 to -32099)
    pub const TOOL_NOT_FOUND: i32 = -32001;
};

/// Constructs a complete JSON-RPC 2.0 error response as an owned byte slice.
///
/// Called throughout main.zig's request loop for parse errors, validation
/// failures, unknown methods, and tool execution errors. The id parameter
/// may be null when the request could not be parsed far enough to extract
/// an id (e.g., JSON parse errors).
pub fn buildErrorResponse(allocator: std.mem.Allocator, id: ?std.json.Value, code: i32, message: []const u8) ![]u8 {
    var buffer = std.ArrayList(u8){};
    errdefer buffer.deinit(allocator);

    var writer = buffer.writer(allocator);

    try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");

    // Serialize id (can be integer, string, or null)
    if (id) |id_val| {
        try serializeId(writer, id_val);
    } else {
        try writer.writeAll("null");
    }

    try writer.writeAll(",\"error\":{\"code\":");
    try writer.print("{d}", .{code});
    try writer.writeAll(",\"message\":\"");
    // Escape message for JSON
    try writeJsonEscapedString(writer, message);
    try writer.writeAll("\"}}");

    return try buffer.toOwnedSlice(allocator);
}

/// Serialize a JSON-RPC id value (integer, string, or null)
pub fn serializeId(writer: anytype, id: std.json.Value) !void {
    switch (id) {
        .integer => |i| try writer.print("{d}", .{i}),
        .string => |s| {
            try writer.writeByte('"');
            try writeJsonEscapedString(writer, s);
            try writer.writeByte('"');
        },
        else => try writer.writeAll("null"),
    }
}

/// Write a JSON-escaped string (without surrounding quotes)
pub fn writeJsonEscapedString(writer: anytype, str: []const u8) !void {
    for (str) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    // Control characters - encode as \u00XX
                    try writer.print("\\u{x:0>4}", .{c});
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
}

/// Wraps a pre-serialized JSON result string in a JSON-RPC 2.0 success envelope.
///
/// Called by main.handleInitialize, handlePing, handleToolsList, and
/// handleToolsCall to produce the final response written to stdout.
pub fn buildSuccessResponse(allocator: std.mem.Allocator, id: std.json.Value, result_json: []const u8) ![]u8 {
    var buffer = std.ArrayList(u8){};
    errdefer buffer.deinit(allocator);

    const writer = buffer.writer(allocator);

    try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try serializeId(writer, id);
    try writer.writeAll(",\"result\":");
    try writer.writeAll(result_json);
    try writer.writeByte('}');

    return try buffer.toOwnedSlice(allocator);
}

/// Wraps tool output in the MCP content array format for tools/call responses.
///
/// Called by main.handleToolsCall after executeStump completes. The text_json
/// is the serialized tree or error JSON. When is_error is true (e.g., token
/// limit exceeded or large directory), the isError flag is added per the MCP
/// specification so clients can distinguish tool errors from protocol errors.
pub fn buildToolContent(allocator: std.mem.Allocator, text_json: []const u8, is_error: bool) ![]u8 {
    var buffer = std.ArrayList(u8){};
    errdefer buffer.deinit(allocator);

    const writer = buffer.writer(allocator);

    try writer.writeAll("{\"content\":[{\"type\":\"text\",\"text\":\"");
    try writeJsonEscapedString(writer, text_json);
    try writer.writeAll("\"}]");
    if (is_error) {
        try writer.writeAll(",\"isError\":true");
    }
    try writer.writeByte('}');

    return try buffer.toOwnedSlice(allocator);
}

/// Tracks request IDs marked for cancellation via "notifications/cancelled".
///
/// Owned by main.zig's MCP request loop. When a cancelled notification arrives,
/// the request ID is stored here. Before processing each incoming request,
/// main checks isCancelled and skips the request if it was pre-emptively
/// cancelled. Since the server is synchronous, cancellation only applies to
/// requests that have not yet started processing.
pub const CancellationTracker = struct {
    /// Set of cancelled request IDs (stored as integers for simplicity)
    cancelled_ids: std.AutoHashMap(i64, void),
    /// Set of cancelled string request IDs
    cancelled_string_ids: std.StringHashMap(void),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CancellationTracker {
        return .{
            .cancelled_ids = std.AutoHashMap(i64, void).init(allocator),
            .cancelled_string_ids = std.StringHashMap(void).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CancellationTracker) void {
        // Free all allocated string keys
        var it = self.cancelled_string_ids.keyIterator();
        while (it.next()) |key| {
            self.allocator.free(key.*);
        }
        self.cancelled_string_ids.deinit();
        self.cancelled_ids.deinit();
    }

    /// Mark a request as cancelled by its ID
    pub fn cancel(self: *CancellationTracker, id: std.json.Value) !void {
        switch (id) {
            .integer => |i| try self.cancelled_ids.put(i, {}),
            .string => |s| {
                const key = try self.allocator.dupe(u8, s);
                errdefer self.allocator.free(key);
                try self.cancelled_string_ids.put(key, {});
            },
            else => {}, // Ignore null or other ID types
        }
    }

    /// Check if a request has been cancelled
    pub fn isCancelled(self: *const CancellationTracker, id: std.json.Value) bool {
        return switch (id) {
            .integer => |i| self.cancelled_ids.contains(i),
            .string => |s| self.cancelled_string_ids.contains(s),
            else => false,
        };
    }

    /// Remove a request ID from the cancelled set (cleanup after handling)
    pub fn remove(self: *CancellationTracker, id: std.json.Value) void {
        switch (id) {
            .integer => |i| _ = self.cancelled_ids.remove(i),
            .string => |s| {
                if (self.cancelled_string_ids.fetchRemove(s)) |entry| {
                    self.allocator.free(entry.key);
                }
            },
            else => {},
        }
    }

    /// Clear all cancelled IDs
    pub fn clear(self: *CancellationTracker) void {
        var it = self.cancelled_string_ids.keyIterator();
        while (it.next()) |key| {
            self.allocator.free(key.*);
        }
        self.cancelled_string_ids.clearRetainingCapacity();
        self.cancelled_ids.clearRetainingCapacity();
    }
};
