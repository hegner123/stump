const std = @import("std");

/// MCP protocol state machine
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
            .initializing => std.mem.eql(u8, method, "initialized") or
                std.mem.eql(u8, method, "notifications/cancelled"),
            .ready => !std.mem.eql(u8, method, "initialize"),
        };
    }

    /// Get the next state after processing a method
    pub fn nextState(self: ProtocolState, method: []const u8) ProtocolState {
        return switch (self) {
            .uninitialized => if (std.mem.eql(u8, method, "initialize")) .initializing else self,
            .initializing => if (std.mem.eql(u8, method, "initialized")) .ready else self,
            .ready => self,
        };
    }
};

/// Check if a method is a notification (no id field, no response expected)
pub fn isNotification(method: []const u8) bool {
    return std.mem.eql(u8, method, "initialized") or
        std.mem.startsWith(u8, method, "notifications/");
}

/// JSON-RPC 2.0 standard error codes
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

/// Build a JSON-RPC 2.0 error response
/// id can be null (for parse errors where id couldn't be determined)
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

/// Build a JSON-RPC 2.0 success response
/// result_json should be a valid JSON string (already serialized)
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

/// Build a tool result content wrapper for MCP tools/call responses
/// text_json should be a valid JSON string (already serialized, including quotes)
/// If is_error is true, adds the isError:true flag per MCP spec
pub fn buildToolContent(allocator: std.mem.Allocator, text_json: []const u8, is_error: bool) ![]u8 {
    var buffer = std.ArrayList(u8){};
    errdefer buffer.deinit(allocator);

    const writer = buffer.writer(allocator);

    try writer.writeAll("{\"content\":[{\"type\":\"text\",\"text\":");
    try writer.writeAll(text_json);
    if (is_error) {
        try writer.writeAll(",\"isError\":true");
    }
    try writer.writeAll("}]}");

    return try buffer.toOwnedSlice(allocator);
}

/// Tracks cancelled request IDs for the notifications/cancelled feature
/// Note: In a synchronous server, cancellation can only be checked at natural
/// checkpoints (e.g., between directory entries during traversal).
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
