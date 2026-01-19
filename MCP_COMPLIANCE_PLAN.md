# MCP Compliance Implementation Plan

## Overview

This plan addresses MCP protocol compliance issues identified in `src/main.zig`. The fixes are prioritized by impact on protocol correctness.

## Current State

- Basic MCP functionality works (initialize, tools/list, tools/call)
- Missing proper error responses (critical)
- String ID support broken (medium)
- Missing protocol state tracking (medium)
- Missing optional MCP methods (low)

---

## Step 1: Proper JSON-RPC Error Responses (Critical)

**Goal**: Return proper JSON-RPC 2.0 error responses instead of logging to stderr and continuing.

**Changes to `src/main.zig`**:

1. Add error response helper function:
```zig
fn buildErrorResponse(allocator: Allocator, id: ?std.json.Value, code: i32, message: []const u8) ![]u8
```

2. Define standard JSON-RPC error codes as constants:
```zig
const PARSE_ERROR = -32700;
const INVALID_REQUEST = -32600;
const METHOD_NOT_FOUND = -32601;
const INVALID_PARAMS = -32602;
const INTERNAL_ERROR = -32603;
```

3. Update main loop to catch errors and return proper error responses:
   - JSON parse errors → code -32700
   - Missing method/id → code -32600
   - Unknown method → code -32601
   - Invalid/missing params → code -32602

**Files**: `src/main.zig`
**Tests**: `test/unit/mcp_test.zig` (new)

---

## Step 2: String and Integer ID Support (Medium)

**Goal**: Properly handle both string and integer IDs per JSON-RPC 2.0 spec.

**Changes to `src/main.zig`**:

1. Create ID serialization helper:
```zig
fn serializeId(writer: anytype, id: std.json.Value) !void {
    switch (id) {
        .integer => |i| try writer.print("{d}", .{i}),
        .string => |s| try writer.print("\"{s}\"", .{s}),
        else => try writer.writeAll("null"),
    }
}
```

2. Update all response builders to use this helper instead of assuming integer ID

3. Handle null ID for notifications (no response needed)

**Files**: `src/main.zig`
**Tests**: `test/unit/mcp_test.zig`

---

## Step 3: Protocol State Tracking (Medium)

**Goal**: Track initialization state and validate request sequence.

**Changes to `src/main.zig`**:

1. Add protocol state enum:
```zig
const ProtocolState = enum {
    uninitialized,
    initializing,
    ready,
};
```

2. Add state variable to main loop

3. Handle `initialized` notification:
   - After client receives initialize response, client sends `initialized` notification
   - Notification has no `id` field (do not respond)
   - Transition state to `ready`

4. Validate state before processing requests:
   - `initialize` only valid in `uninitialized` state
   - Other methods only valid in `ready` state
   - Return error -32600 if state invalid

**Files**: `src/main.zig`
**Tests**: `test/unit/mcp_test.zig`

---

## Step 4: Request Validation (Low)

**Goal**: Validate incoming requests per JSON-RPC 2.0 spec.

**Changes to `src/main.zig`**:

1. Verify `jsonrpc` field equals "2.0"

2. In `tools/call`, verify `params.name` matches "stump":
```zig
const tool_name = params.object.get("name") orelse return error.InvalidParams;
if (!std.mem.eql(u8, tool_name.string, "stump")) {
    return error.ToolNotFound;
}
```

3. Add new error code for unknown tool:
```zig
const TOOL_NOT_FOUND = -32001; // Application-defined error
```

**Files**: `src/main.zig`
**Tests**: `test/unit/mcp_test.zig`

---

## Step 5: Add `isError` Content Flag (Low)

**Goal**: Mark error content with `isError: true` per MCP spec.

**Changes**:

1. Update `handleToolsCall` error responses to include `isError` flag:
```json
{"type":"text","text":"...error message...","isError":true}
```

2. Update `output.zig` error serialization functions to support this flag

**Files**: `src/main.zig`, `src/output.zig`
**Tests**: `test/unit/mcp_test.zig`, `test/unit/output_test.zig`

---

## Step 6: Add `ping` Method (Optional)

**Goal**: Support connection health checks.

**Changes to `src/main.zig`**:

1. Add handler for `ping` method:
```zig
fn handlePing(allocator: Allocator, id: std.json.Value) ![]u8 {
    // Return empty result: {"jsonrpc":"2.0","id":...,"result":{}}
}
```

2. Add to method dispatch in `processRequest`

**Files**: `src/main.zig`
**Tests**: `test/unit/mcp_test.zig`

---

## Step 7: Add Cancellation Support (Optional)

**Goal**: Handle `notifications/cancelled` for long-running operations.

**Changes**:

1. Add cancellation token/flag to traversal state

2. Handle `notifications/cancelled` notification:
   - Extract `requestId` from params
   - Set cancellation flag for matching in-progress request

3. Check cancellation flag during tree traversal

**Note**: This is complex because current implementation is synchronous. May require async refactoring or periodic cancellation checks during traversal.

**Files**: `src/main.zig`, `src/tree.zig`, `src/types.zig`
**Tests**: `test/unit/mcp_test.zig`

---

## Implementation Order

| Step | Priority | Complexity | Dependencies |
|------|----------|------------|--------------|
| 1    | Critical | Low        | None         |
| 2    | Medium   | Low        | None         |
| 3    | Medium   | Medium     | Step 1       |
| 4    | Low      | Low        | Step 1       |
| 5    | Low      | Low        | None         |
| 6    | Optional | Low        | Step 1, 2    |
| 7    | Optional | High       | Step 1, 2, 3 |

**Recommended approach**: Steps 1-4 can be done in a single pass. Steps 5-6 are quick additions. Step 7 is optional and significantly more complex.

---

## Testing Strategy

Create `test/unit/mcp_test.zig` with:

1. **Error response tests**:
   - Parse error returns -32700
   - Missing method returns -32600
   - Unknown method returns -32601
   - Invalid params returns -32602

2. **ID handling tests**:
   - Integer ID echoed correctly
   - String ID echoed correctly
   - Null ID for notifications (no response)

3. **State machine tests**:
   - Requests before initialize rejected
   - initialized notification transitions state
   - Normal flow works after initialization

4. **Validation tests**:
   - Missing jsonrpc field rejected
   - Wrong tool name rejected

---

## Success Criteria

- [ ] All error conditions return proper JSON-RPC error responses
- [ ] Both string and integer IDs work correctly
- [ ] Protocol state is tracked and validated
- [ ] Request fields are validated
- [ ] Error content includes `isError` flag
- [ ] `ping` method responds correctly
- [ ] All new tests pass
- [ ] Existing functionality unchanged
