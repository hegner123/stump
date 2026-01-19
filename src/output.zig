const std = @import("std");
const types = @import("types.zig");
const performance = @import("performance.zig");

/// Generate a UUID v4 for unique filenames
pub fn generateUUID() [36]u8 {
    var uuid: [36]u8 = undefined;
    var random_bytes: [16]u8 = undefined;

    // Get random bytes
    std.crypto.random.bytes(&random_bytes);

    // Set version (4) and variant bits
    random_bytes[6] = (random_bytes[6] & 0x0f) | 0x40; // Version 4
    random_bytes[8] = (random_bytes[8] & 0x3f) | 0x80; // Variant 10

    // Format as UUID string: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
    _ = std.fmt.bufPrint(&uuid, "{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{
        random_bytes[0], random_bytes[1], random_bytes[2],  random_bytes[3],
        random_bytes[4], random_bytes[5], random_bytes[6],  random_bytes[7],
        random_bytes[8], random_bytes[9], random_bytes[10], random_bytes[11],
        random_bytes[12], random_bytes[13], random_bytes[14], random_bytes[15],
    }) catch unreachable;

    return uuid;
}

/// Generate a unique filename by incorporating UUID
/// If base_path is null, returns a temp file path
/// Otherwise, inserts UUID before the extension
pub fn generateUniqueFilename(allocator: std.mem.Allocator, base_path: ?[]const u8) ![]u8 {
    const uuid = generateUUID();

    if (base_path) |path| {
        // Find the extension
        const ext_idx = std.mem.lastIndexOfScalar(u8, path, '.');

        if (ext_idx) |idx| {
            // Insert UUID before extension: /path/to/file-<uuid>.json
            const base = path[0..idx];
            const ext = path[idx..];
            return try std.fmt.allocPrint(allocator, "{s}-{s}{s}", .{ base, &uuid, ext });
        } else {
            // No extension, append UUID: /path/to/file-<uuid>
            return try std.fmt.allocPrint(allocator, "{s}-{s}", .{ path, &uuid });
        }
    } else {
        // Use temp directory with UUID
        return try std.fmt.allocPrint(allocator, "/tmp/stump-{s}.json", .{&uuid});
    }
}

/// Estimate token count from byte count (4 chars per token approximation)
pub fn estimateTokenCount(byte_count: u64) u64 {
    return byte_count / 4;
}

/// Calculate byte limit from token limit
pub fn calculateByteLimit(token_limit: u64) u64 {
    return token_limit * 4;
}

/// JSON writer for streaming output to file or memory
pub const JsonWriter = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    file: ?std.fs.File,
    byte_limit: ?u64, // Only enforced in stdout mode (when file is null)
    current_bytes: u64,

    pub fn init(allocator: std.mem.Allocator, output_file: ?[]const u8, byte_limit: ?u64) !JsonWriter {
        const file: ?std.fs.File = null;

        // If output_file specified, open file for writing
        if (output_file) |_| {
            // File will be opened later with unique filename
            // For now, mark as file mode by setting byte_limit to null
        }

        return JsonWriter{
            .allocator = allocator,
            .buffer = std.ArrayList(u8){},
            .file = file,
            .byte_limit = if (output_file == null) byte_limit else null,
            .current_bytes = 0,
        };
    }

    pub fn deinit(self: *JsonWriter) void {
        self.buffer.deinit(self.allocator);
        if (self.file) |f| {
            f.close();
        }
    }

    /// Write bytes to buffer or file
    pub fn write(self: *JsonWriter, bytes: []const u8) !void {
        // Check byte limit for stdout mode
        if (self.byte_limit) |limit| {
            if (self.current_bytes + bytes.len > limit) {
                return error.TokenLimitExceeded;
            }
        }

        if (self.file) |f| {
            // File mode: write directly to file
            try f.writeAll(bytes);
        } else {
            // Stdout mode: accumulate in buffer
            try self.buffer.appendSlice(bytes);
        }

        self.current_bytes += bytes.len;
    }

    /// Get the accumulated buffer (stdout mode only)
    pub fn getBuffer(self: *const JsonWriter) []const u8 {
        return self.buffer.items;
    }

    /// Get current byte count
    pub fn getByteCount(self: *const JsonWriter) u64 {
        return self.current_bytes;
    }
};

/// Serialize OutputData to JSON and write to stdout or file
pub fn serializeToStdout(
    allocator: std.mem.Allocator,
    data: *const types.OutputData,
    perf_tracker: *performance.PerformanceTracker,
) ![]u8 {
    perf_tracker.startSerialization();
    defer perf_tracker.stopSerialization();

    var buffer = std.ArrayList(u8){};
    errdefer buffer.deinit(allocator);

    try writeJson(allocator, &buffer, data);

    const result = try buffer.toOwnedSlice(allocator);
    perf_tracker.recordOutputBytes(result.len);

    return result;
}

/// Serialize OutputData to JSON and write to file
pub fn serializeToFile(
    allocator: std.mem.Allocator,
    data: *const types.OutputData,
    output_file: ?[]const u8,
    perf_tracker: *performance.PerformanceTracker,
) !types.FileOutputSuccess {
    perf_tracker.startSerialization();
    defer perf_tracker.stopSerialization();

    // Generate unique filename
    const unique_filename = try generateUniqueFilename(allocator, output_file);
    errdefer allocator.free(unique_filename);

    // Open file for writing
    const file = try std.fs.cwd().createFile(unique_filename, .{});
    defer file.close();

    // Write JSON to file
    var buffer = std.ArrayList(u8){};
    defer buffer.deinit(allocator);

    try writeJson(allocator, &buffer, data);
    try file.writeAll(buffer.items);

    perf_tracker.recordOutputBytes(buffer.items.len);

    // Create success response
    const message = try std.fmt.allocPrint(allocator, "Tree written to {s}", .{unique_filename});

    return types.FileOutputSuccess{
        .success = true,
        .message = message,
        .stats = data.stats,
    };
}

/// Write JSON to a buffer
fn writeJson(allocator: std.mem.Allocator, buffer: *std.ArrayList(u8), data: *const types.OutputData) !void {
    const writer = buffer.writer(allocator);

    try writer.writeAll("{");

    // Write root
    try writer.writeAll("\"root\":");
    try writeJsonString(allocator, buffer, data.root);
    try writer.writeAll(",");

    // Write depth
    try writer.print("\"depth\":{d},", .{data.depth});

    // Write stats
    try writer.writeAll("\"stats\":{");
    try writer.print("\"dirs\":{d},", .{data.stats.dirs});
    try writer.print("\"files\":{d},", .{data.stats.files});
    try writer.print("\"filtered\":{d},", .{data.stats.filtered});
    try writer.print("\"symlinks\":{d}", .{data.stats.symlinks});
    if (data.stats.aborted_at) |aborted| {
        try writer.print(",\"aborted_at\":{d}", .{aborted});
    }
    if (data.stats.token_limit) |limit| {
        try writer.print(",\"token_limit\":{d}", .{limit});
    }
    try writer.writeAll("},");

    // Write tree array
    try writer.writeAll("\"tree\":[");
    for (data.tree, 0..) |entry, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.writeAll("{");
        try writer.writeAll("\"path\":");
        try writeJsonString(allocator, buffer, entry.path);
        try writer.writeAll(",\"type\":\"");
        try writer.writeAll(entry.type.toString());
        try writer.writeAll("\"");
        if (entry.size) |size| {
            try writer.print(",\"size\":{d}", .{size});
        }
        try writer.writeAll("}");
    }
    try writer.writeAll("]");

    // Write optional symlinks_detected array
    if (data.symlinks_detected) |symlinks| {
        try writer.writeAll(",\"symlinks_detected\":[");
        for (symlinks, 0..) |symlink, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.writeAll("{\"path\":");
            try writeJsonString(allocator, buffer, symlink.path);
            try writer.writeAll(",\"target\":");
            try writeJsonString(allocator, buffer, symlink.target);
            try writer.writeAll("}");
        }
        try writer.writeAll("]");
    }

    // Write optional errors array
    if (data.errors) |errors| {
        try writer.writeAll(",\"errors\":[");
        for (errors, 0..) |err, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.writeAll("{\"type\":\"");
            try writer.writeAll(err.type.toString());
            try writer.writeAll("\",\"path\":");
            try writeJsonString(allocator, buffer, err.path);
            try writer.writeAll(",\"message\":");
            try writeJsonString(allocator, buffer, err.message);
            if (err.target) |target| {
                try writer.writeAll(",\"target\":");
                try writeJsonString(allocator, buffer, target);
            }
            try writer.writeAll("}");
        }
        try writer.writeAll("]");
    }

    // Write optional performance object
    if (data.performance) |perf| {
        try writer.writeAll(",\"performance\":{");
        try writer.print("\"total_ms\":{d},", .{perf.total_ms});
        try writer.print("\"traversal_ms\":{d},", .{perf.traversal_ms});
        try writer.print("\"filtering_ms\":{d},", .{perf.filtering_ms});
        try writer.print("\"serialization_ms\":{d},", .{perf.serialization_ms});
        try writer.print("\"peak_memory_bytes\":{d},", .{perf.peak_memory_bytes});
        try writer.print("\"final_memory_bytes\":{d},", .{perf.final_memory_bytes});
        try writer.print("\"allocations\":{d},", .{perf.allocations});
        try writer.print("\"stat_calls\":{d},", .{perf.stat_calls});
        try writer.print("\"readdir_calls\":{d},", .{perf.readdir_calls});
        try writer.print("\"symlink_resolutions\":{d},", .{perf.symlink_resolutions});
        try writer.print("\"items_per_second\":{d},", .{perf.items_per_second});
        try writer.print("\"bytes_per_second\":{d},", .{perf.bytes_per_second});
        try writer.print("\"avg_time_per_item_us\":{d},", .{perf.avg_time_per_item_us});
        try writer.print("\"filter_efficiency\":{d:.1},", .{perf.filter_efficiency});
        try writer.print("\"cache_hits\":{d}", .{perf.cache_hits});
        try writer.writeAll("}");
    }

    // Write optional _note field
    if (data._note) |note| {
        try writer.writeAll(",\"_note\":");
        try writeJsonString(allocator, buffer, note);
    }

    try writer.writeAll("}");
}

/// Write a JSON-escaped string
fn writeJsonString(allocator: std.mem.Allocator, buffer: *std.ArrayList(u8), s: []const u8) !void {
    const writer = buffer.writer(allocator);
    try writer.writeAll("\"");

    for (s) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            0x00...0x08, 0x0B...0x0C, 0x0E...0x1F => try writer.print("\\u{x:0>4}", .{c}),
            else => try writer.writeByte(c),
        }
    }

    try writer.writeAll("\"");
}

/// Serialize a fatal error to JSON
pub fn serializeFatalError(
    allocator: std.mem.Allocator,
    fatal_error: *const types.FatalError,
) ![]u8 {
    var buffer = std.ArrayList(u8){};
    errdefer buffer.deinit(allocator);

    const writer = buffer.writer(allocator);

    try writer.writeAll("{");
    try writer.writeAll("\"error\":");
    try writeJsonString(allocator, &buffer, fatal_error.error_name);
    try writer.writeAll(",\"type\":\"");
    try writer.writeAll(fatal_error.type.toString());
    try writer.writeAll("\",\"path\":");
    try writeJsonString(allocator, &buffer, fatal_error.path);
    try writer.writeAll(",\"message\":");
    try writeJsonString(allocator, &buffer, fatal_error.message);
    try writer.writeAll("}");

    return try buffer.toOwnedSlice(allocator);
}

/// Serialize token limit exceeded error to JSON
pub fn serializeTokenLimitError(
    allocator: std.mem.Allocator,
    stats: *const types.Stats,
    aborted_at: u64,
    token_limit: u64,
) ![]u8 {
    var buffer = std.ArrayList(u8){};
    errdefer buffer.deinit(allocator);

    const writer = buffer.writer(allocator);

    try writer.writeAll("{");
    try writer.writeAll("\"error\":\"Token limit exceeded\",");
    try writer.print("\"message\":\"Tree output would exceed token limit ({d} tokens, ~{d} bytes). Use 'output_file' parameter to save to file instead, or increase 'token_limit' (range: 1000-100000).\",", .{
        token_limit,
        aborted_at,
    });
    try writer.writeAll("\"stats\":{");
    try writer.print("\"dirs\":{d},", .{stats.dirs});
    try writer.print("\"files\":{d},", .{stats.files});
    try writer.print("\"aborted_at\":{d},", .{aborted_at});
    try writer.print("\"token_limit\":{d}", .{token_limit});
    try writer.writeAll("}}");

    return try buffer.toOwnedSlice(allocator);
}

test "generateUUID" {
    const uuid1 = generateUUID();
    const uuid2 = generateUUID();

    // UUIDs should be different
    try std.testing.expect(!std.mem.eql(u8, &uuid1, &uuid2));

    // Should have correct format (8-4-4-4-12)
    try std.testing.expectEqual(@as(usize, 36), uuid1.len);
    try std.testing.expectEqual('-', uuid1[8]);
    try std.testing.expectEqual('-', uuid1[13]);
    try std.testing.expectEqual('-', uuid1[18]);
    try std.testing.expectEqual('-', uuid1[23]);
}

test "generateUniqueFilename" {
    const allocator = std.testing.allocator;

    // Test with null path (temp file)
    {
        const filename = try generateUniqueFilename(allocator, null);
        defer allocator.free(filename);

        try std.testing.expect(std.mem.startsWith(u8, filename, "/tmp/stump-"));
        try std.testing.expect(std.mem.endsWith(u8, filename, ".json"));
    }

    // Test with path with extension
    {
        const filename = try generateUniqueFilename(allocator, "/tmp/output.json");
        defer allocator.free(filename);

        try std.testing.expect(std.mem.startsWith(u8, filename, "/tmp/output-"));
        try std.testing.expect(std.mem.endsWith(u8, filename, ".json"));
    }

    // Test with path without extension
    {
        const filename = try generateUniqueFilename(allocator, "/tmp/output");
        defer allocator.free(filename);

        try std.testing.expect(std.mem.startsWith(u8, filename, "/tmp/output-"));
    }
}

test "estimateTokenCount" {
    try std.testing.expectEqual(@as(u64, 10), estimateTokenCount(40));
    try std.testing.expectEqual(@as(u64, 100), estimateTokenCount(400));
    try std.testing.expectEqual(@as(u64, 10000), estimateTokenCount(40000));
}

test "calculateByteLimit" {
    try std.testing.expectEqual(@as(u64, 40), calculateByteLimit(10));
    try std.testing.expectEqual(@as(u64, 400), calculateByteLimit(100));
    try std.testing.expectEqual(@as(u64, 40000), calculateByteLimit(10000));
}

test "writeJsonString" {
    const allocator = std.testing.allocator;

    var buffer = std.ArrayList(u8){};
    defer buffer.deinit(allocator);

    try writeJsonString(allocator, &buffer, "hello \"world\"");
    try std.testing.expectEqualStrings("\"hello \\\"world\\\"\"", buffer.items);

    buffer.clearRetainingCapacity();
    try writeJsonString(allocator, &buffer, "line1\nline2");
    try std.testing.expectEqualStrings("\"line1\\nline2\"", buffer.items);
}

test "serializeFatalError" {
    const allocator = std.testing.allocator;

    var fatal_error = try types.FatalError.init(
        allocator,
        .large_directory,
        "/home/user",
        "Refusing to traverse",
    );
    defer fatal_error.deinit(allocator);

    const json = try serializeFatalError(allocator, &fatal_error);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"error\":\"Large directory detected\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\":\"large_directory\"") != null);
}
