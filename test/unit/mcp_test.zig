const std = @import("std");
const testing = std.testing;
const mcp = @import("stump").mcp;

test "JsonRpcError constants have correct values" {
    // Standard JSON-RPC 2.0 errors
    try testing.expectEqual(@as(i32, -32700), mcp.JsonRpcError.PARSE_ERROR);
    try testing.expectEqual(@as(i32, -32600), mcp.JsonRpcError.INVALID_REQUEST);
    try testing.expectEqual(@as(i32, -32601), mcp.JsonRpcError.METHOD_NOT_FOUND);
    try testing.expectEqual(@as(i32, -32602), mcp.JsonRpcError.INVALID_PARAMS);
    try testing.expectEqual(@as(i32, -32603), mcp.JsonRpcError.INTERNAL_ERROR);

    // Application-defined errors (must be in range -32000 to -32099)
    try testing.expectEqual(@as(i32, -32001), mcp.JsonRpcError.TOOL_NOT_FOUND);
    try testing.expect(mcp.JsonRpcError.TOOL_NOT_FOUND >= -32099);
    try testing.expect(mcp.JsonRpcError.TOOL_NOT_FOUND <= -32000);
}

test "buildErrorResponse with null id" {
    const allocator = testing.allocator;

    const response = try mcp.buildErrorResponse(
        allocator,
        null,
        mcp.JsonRpcError.PARSE_ERROR,
        "Parse error: invalid JSON",
    );
    defer allocator.free(response);

    // Parse the response to verify it's valid JSON
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;

    // Verify jsonrpc version
    try testing.expectEqualStrings("2.0", obj.get("jsonrpc").?.string);

    // Verify id is null
    try testing.expect(obj.get("id").? == .null);

    // Verify error object
    const err = obj.get("error").?.object;
    try testing.expectEqual(@as(i64, -32700), err.get("code").?.integer);
    try testing.expectEqualStrings("Parse error: invalid JSON", err.get("message").?.string);
}

test "buildErrorResponse with integer id" {
    const allocator = testing.allocator;

    // Create a JSON integer value for id
    const id_value = std.json.Value{ .integer = 42 };

    const response = try mcp.buildErrorResponse(
        allocator,
        id_value,
        mcp.JsonRpcError.INVALID_REQUEST,
        "Invalid Request: missing required fields",
    );
    defer allocator.free(response);

    // Parse the response
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;

    // Verify id is echoed correctly
    try testing.expectEqual(@as(i64, 42), obj.get("id").?.integer);

    // Verify error code
    const err = obj.get("error").?.object;
    try testing.expectEqual(@as(i64, -32600), err.get("code").?.integer);
}

test "buildErrorResponse with string id" {
    const allocator = testing.allocator;

    // Create a JSON string value for id
    const id_value = std.json.Value{ .string = "request-123" };

    const response = try mcp.buildErrorResponse(
        allocator,
        id_value,
        mcp.JsonRpcError.METHOD_NOT_FOUND,
        "Method not found",
    );
    defer allocator.free(response);

    // Parse the response
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;

    // Verify string id is echoed correctly
    try testing.expectEqualStrings("request-123", obj.get("id").?.string);

    // Verify error code
    const err = obj.get("error").?.object;
    try testing.expectEqual(@as(i64, -32601), err.get("code").?.integer);
}

test "buildErrorResponse escapes special characters in message" {
    const allocator = testing.allocator;

    const response = try mcp.buildErrorResponse(
        allocator,
        null,
        mcp.JsonRpcError.INTERNAL_ERROR,
        "Error with \"quotes\" and \\ backslash and \n newline",
    );
    defer allocator.free(response);

    // Parse the response - if JSON parsing succeeds, escaping worked
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    const err = parsed.value.object.get("error").?.object;
    const message = err.get("message").?.string;

    // Verify the message contains the special characters (unescaped after parsing)
    try testing.expect(std.mem.indexOf(u8, message, "\"quotes\"") != null);
    try testing.expect(std.mem.indexOf(u8, message, "\\") != null);
    try testing.expect(std.mem.indexOf(u8, message, "\n") != null);
}

test "buildErrorResponse with INVALID_PARAMS error" {
    const allocator = testing.allocator;

    const id_value = std.json.Value{ .integer = 1 };

    const response = try mcp.buildErrorResponse(
        allocator,
        id_value,
        mcp.JsonRpcError.INVALID_PARAMS,
        "Invalid params: missing required 'dir' parameter",
    );
    defer allocator.free(response);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    const err = parsed.value.object.get("error").?.object;
    try testing.expectEqual(@as(i64, -32602), err.get("code").?.integer);
    try testing.expect(std.mem.indexOf(u8, err.get("message").?.string, "dir") != null);
}

test "writeJsonEscapedString handles all escape sequences" {
    const allocator = testing.allocator;
    var buffer = std.ArrayList(u8){};
    defer buffer.deinit(allocator);

    const writer = buffer.writer(allocator);

    // Test string with all escape characters
    try mcp.writeJsonEscapedString(writer, "tab:\there\nnewline\rcarriage\"quote\\backslash");

    const result = buffer.items;

    // Verify escape sequences are present
    try testing.expect(std.mem.indexOf(u8, result, "\\t") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\\n") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\\r") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\\\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\\\\") != null);
}

test "serializeId handles integer" {
    const allocator = testing.allocator;
    var buffer = std.ArrayList(u8){};
    defer buffer.deinit(allocator);

    const writer = buffer.writer(allocator);
    try mcp.serializeId(writer, std.json.Value{ .integer = 123 });

    try testing.expectEqualStrings("123", buffer.items);
}

test "serializeId handles string" {
    const allocator = testing.allocator;
    var buffer = std.ArrayList(u8){};
    defer buffer.deinit(allocator);

    const writer = buffer.writer(allocator);
    try mcp.serializeId(writer, std.json.Value{ .string = "abc" });

    try testing.expectEqualStrings("\"abc\"", buffer.items);
}

test "serializeId handles null" {
    const allocator = testing.allocator;
    var buffer = std.ArrayList(u8){};
    defer buffer.deinit(allocator);

    const writer = buffer.writer(allocator);
    try mcp.serializeId(writer, std.json.Value.null);

    try testing.expectEqualStrings("null", buffer.items);
}

test "buildSuccessResponse with integer id" {
    const allocator = testing.allocator;

    const id_value = std.json.Value{ .integer = 42 };
    const response = try mcp.buildSuccessResponse(
        allocator,
        id_value,
        "{\"data\":\"test\"}",
    );
    defer allocator.free(response);

    // Parse and verify
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;

    try testing.expectEqualStrings("2.0", obj.get("jsonrpc").?.string);
    try testing.expectEqual(@as(i64, 42), obj.get("id").?.integer);

    const result = obj.get("result").?.object;
    try testing.expectEqualStrings("test", result.get("data").?.string);
}

test "buildSuccessResponse with string id" {
    const allocator = testing.allocator;

    const id_value = std.json.Value{ .string = "req-abc-123" };
    const response = try mcp.buildSuccessResponse(
        allocator,
        id_value,
        "{\"status\":\"ok\"}",
    );
    defer allocator.free(response);

    // Parse and verify
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;

    try testing.expectEqualStrings("2.0", obj.get("jsonrpc").?.string);
    try testing.expectEqualStrings("req-abc-123", obj.get("id").?.string);

    const result = obj.get("result").?.object;
    try testing.expectEqualStrings("ok", result.get("status").?.string);
}

test "buildSuccessResponse with complex result" {
    const allocator = testing.allocator;

    const id_value = std.json.Value{ .integer = 1 };
    const response = try mcp.buildSuccessResponse(
        allocator,
        id_value,
        "{\"content\":[{\"type\":\"text\",\"text\":\"hello\"}]}",
    );
    defer allocator.free(response);

    // Parse and verify
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;
    const result = obj.get("result").?.object;
    const content = result.get("content").?.array;

    try testing.expectEqual(@as(usize, 1), content.items.len);
    try testing.expectEqualStrings("text", content.items[0].object.get("type").?.string);
    try testing.expectEqualStrings("hello", content.items[0].object.get("text").?.string);
}

test "serializeId escapes special characters in string id" {
    const allocator = testing.allocator;
    var buffer = std.ArrayList(u8){};
    defer buffer.deinit(allocator);

    const writer = buffer.writer(allocator);
    try mcp.serializeId(writer, std.json.Value{ .string = "id\"with\\special" });

    // Should be properly escaped
    try testing.expectEqualStrings("\"id\\\"with\\\\special\"", buffer.items);
}

// Protocol State Tests

test "ProtocolState.uninitialized only allows initialize" {
    const state = mcp.ProtocolState.uninitialized;

    // Only initialize should be allowed
    try testing.expect(state.isMethodAllowed("initialize"));

    // Other methods should be rejected
    try testing.expect(!state.isMethodAllowed("tools/list"));
    try testing.expect(!state.isMethodAllowed("tools/call"));
    try testing.expect(!state.isMethodAllowed("initialized"));
    try testing.expect(!state.isMethodAllowed("ping"));
}

test "ProtocolState.initializing allows initialized notification" {
    const state = mcp.ProtocolState.initializing;

    // initialized notification should be allowed
    try testing.expect(state.isMethodAllowed("initialized"));
    try testing.expect(state.isMethodAllowed("notifications/cancelled"));

    // Other methods should be rejected
    try testing.expect(!state.isMethodAllowed("initialize"));
    try testing.expect(!state.isMethodAllowed("tools/list"));
    try testing.expect(!state.isMethodAllowed("tools/call"));
}

test "ProtocolState.ready allows most methods except initialize" {
    const state = mcp.ProtocolState.ready;

    // Normal methods should be allowed
    try testing.expect(state.isMethodAllowed("tools/list"));
    try testing.expect(state.isMethodAllowed("tools/call"));
    try testing.expect(state.isMethodAllowed("ping"));

    // initialize should be rejected (already initialized)
    try testing.expect(!state.isMethodAllowed("initialize"));
}

test "ProtocolState.nextState transitions correctly" {
    // uninitialized -> initializing after initialize
    var state = mcp.ProtocolState.uninitialized;
    state = state.nextState("initialize");
    try testing.expectEqual(mcp.ProtocolState.initializing, state);

    // initializing -> ready after initialized
    state = state.nextState("initialized");
    try testing.expectEqual(mcp.ProtocolState.ready, state);

    // ready stays ready
    state = state.nextState("tools/list");
    try testing.expectEqual(mcp.ProtocolState.ready, state);
}

test "ProtocolState.nextState ignores irrelevant methods" {
    // uninitialized stays uninitialized for non-initialize methods
    var state = mcp.ProtocolState.uninitialized;
    state = state.nextState("tools/list");
    try testing.expectEqual(mcp.ProtocolState.uninitialized, state);

    // initializing stays initializing for non-initialized methods
    state = mcp.ProtocolState.initializing;
    state = state.nextState("tools/list");
    try testing.expectEqual(mcp.ProtocolState.initializing, state);
}

test "isNotification identifies notifications correctly" {
    // Notifications
    try testing.expect(mcp.isNotification("initialized"));
    try testing.expect(mcp.isNotification("notifications/cancelled"));
    try testing.expect(mcp.isNotification("notifications/progress"));

    // Requests (not notifications)
    try testing.expect(!mcp.isNotification("initialize"));
    try testing.expect(!mcp.isNotification("tools/list"));
    try testing.expect(!mcp.isNotification("tools/call"));
    try testing.expect(!mcp.isNotification("ping"));
}

// Tool Content Tests

test "buildToolContent without isError flag" {
    const allocator = testing.allocator;

    const content = try mcp.buildToolContent(allocator, "\"hello world\"", false);
    defer allocator.free(content);

    // Parse and verify
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;
    const content_array = obj.get("content").?.array;

    try testing.expectEqual(@as(usize, 1), content_array.items.len);

    const item = content_array.items[0].object;
    try testing.expectEqualStrings("text", item.get("type").?.string);
    try testing.expectEqualStrings("hello world", item.get("text").?.string);

    // isError should not be present
    try testing.expect(item.get("isError") == null);
}

test "buildToolContent with isError flag" {
    const allocator = testing.allocator;

    const content = try mcp.buildToolContent(allocator, "\"Error: something went wrong\"", true);
    defer allocator.free(content);

    // Parse and verify
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;
    const content_array = obj.get("content").?.array;

    try testing.expectEqual(@as(usize, 1), content_array.items.len);

    const item = content_array.items[0].object;
    try testing.expectEqualStrings("text", item.get("type").?.string);
    try testing.expectEqualStrings("Error: something went wrong", item.get("text").?.string);

    // isError should be true
    try testing.expect(item.get("isError").?.bool == true);
}

test "buildToolContent with complex JSON as text" {
    const allocator = testing.allocator;

    // The text_json parameter should be a valid JSON value (including quotes for strings)
    // For a JSON object as the text, it would be an object literal
    const content = try mcp.buildToolContent(
        allocator,
        "{\"error\":\"Token limit exceeded\",\"stats\":{\"dirs\":10}}",
        true,
    );
    defer allocator.free(content);

    // Parse and verify structure
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;
    const content_array = obj.get("content").?.array;
    const item = content_array.items[0].object;

    // text should be the parsed JSON object
    const text_obj = item.get("text").?.object;
    try testing.expectEqualStrings("Token limit exceeded", text_obj.get("error").?.string);

    // isError should be true
    try testing.expect(item.get("isError").?.bool == true);
}

// Ping Method Tests

test "buildSuccessResponse with empty result for ping" {
    const allocator = testing.allocator;

    // Ping returns an empty result object
    const id_value = std.json.Value{ .integer = 42 };
    const response = try mcp.buildSuccessResponse(allocator, id_value, "{}");
    defer allocator.free(response);

    // Parse and verify
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;

    try testing.expectEqualStrings("2.0", obj.get("jsonrpc").?.string);
    try testing.expectEqual(@as(i64, 42), obj.get("id").?.integer);

    // Result should be an empty object
    const result = obj.get("result").?.object;
    try testing.expectEqual(@as(usize, 0), result.count());
}

test "ping is allowed in ready state" {
    const state = mcp.ProtocolState.ready;
    try testing.expect(state.isMethodAllowed("ping"));
}

test "ping is not allowed before initialization" {
    const uninitialized = mcp.ProtocolState.uninitialized;
    try testing.expect(!uninitialized.isMethodAllowed("ping"));

    const initializing = mcp.ProtocolState.initializing;
    try testing.expect(!initializing.isMethodAllowed("ping"));
}

// Cancellation Tracker Tests

test "CancellationTracker tracks integer IDs" {
    const allocator = testing.allocator;
    var tracker = mcp.CancellationTracker.init(allocator);
    defer tracker.deinit();

    const id = std.json.Value{ .integer = 42 };

    // Initially not cancelled
    try testing.expect(!tracker.isCancelled(id));

    // Cancel it
    try tracker.cancel(id);
    try testing.expect(tracker.isCancelled(id));

    // Remove it
    tracker.remove(id);
    try testing.expect(!tracker.isCancelled(id));
}

test "CancellationTracker tracks string IDs" {
    const allocator = testing.allocator;
    var tracker = mcp.CancellationTracker.init(allocator);
    defer tracker.deinit();

    const id = std.json.Value{ .string = "request-abc-123" };

    // Initially not cancelled
    try testing.expect(!tracker.isCancelled(id));

    // Cancel it
    try tracker.cancel(id);
    try testing.expect(tracker.isCancelled(id));

    // Remove it
    tracker.remove(id);
    try testing.expect(!tracker.isCancelled(id));
}

test "CancellationTracker handles multiple cancellations" {
    const allocator = testing.allocator;
    var tracker = mcp.CancellationTracker.init(allocator);
    defer tracker.deinit();

    const id1 = std.json.Value{ .integer = 1 };
    const id2 = std.json.Value{ .integer = 2 };
    const id3 = std.json.Value{ .string = "req-3" };

    try tracker.cancel(id1);
    try tracker.cancel(id2);
    try tracker.cancel(id3);

    try testing.expect(tracker.isCancelled(id1));
    try testing.expect(tracker.isCancelled(id2));
    try testing.expect(tracker.isCancelled(id3));

    // Remove one
    tracker.remove(id2);
    try testing.expect(tracker.isCancelled(id1));
    try testing.expect(!tracker.isCancelled(id2));
    try testing.expect(tracker.isCancelled(id3));
}

test "CancellationTracker clear removes all" {
    const allocator = testing.allocator;
    var tracker = mcp.CancellationTracker.init(allocator);
    defer tracker.deinit();

    try tracker.cancel(std.json.Value{ .integer = 1 });
    try tracker.cancel(std.json.Value{ .integer = 2 });
    try tracker.cancel(std.json.Value{ .string = "req-3" });

    tracker.clear();

    try testing.expect(!tracker.isCancelled(std.json.Value{ .integer = 1 }));
    try testing.expect(!tracker.isCancelled(std.json.Value{ .integer = 2 }));
    try testing.expect(!tracker.isCancelled(std.json.Value{ .string = "req-3" }));
}

test "CancellationTracker ignores null IDs" {
    const allocator = testing.allocator;
    var tracker = mcp.CancellationTracker.init(allocator);
    defer tracker.deinit();

    const null_id = std.json.Value.null;

    // Should not crash and should return false
    try tracker.cancel(null_id);
    try testing.expect(!tracker.isCancelled(null_id));
    tracker.remove(null_id);
}
