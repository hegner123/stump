const std = @import("std");
const testing = std.testing;
const output = @import("../../src/output.zig");

test "generateUUID creates valid UUID format" {
    const uuid = output.generateUUID();

    // Check length
    try testing.expectEqual(@as(usize, 36), uuid.len);

    // Check format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
    try testing.expectEqual(@as(u8, '-'), uuid[8]);
    try testing.expectEqual(@as(u8, '-'), uuid[13]);
    try testing.expectEqual(@as(u8, '-'), uuid[18]);
    try testing.expectEqual(@as(u8, '-'), uuid[23]);

    // Check version 4 (14th character should be '4')
    try testing.expectEqual(@as(u8, '4'), uuid[14]);
}

test "generateUUID produces unique values" {
    const uuid1 = output.generateUUID();
    const uuid2 = output.generateUUID();

    // UUIDs should be different
    try testing.expect(!std.mem.eql(u8, &uuid1, &uuid2));
}

test "generateUniqueFilename with extension" {
    const allocator = testing.allocator;

    const filename = try output.generateUniqueFilename(allocator, "/path/to/file.json");
    defer allocator.free(filename);

    // Should contain UUID and original extension
    try testing.expect(std.mem.indexOf(u8, filename, "/path/to/file-") != null);
    try testing.expect(std.mem.endsWith(u8, filename, ".json"));
    try testing.expect(filename.len > "/path/to/file-.json".len);
}

test "generateUniqueFilename without extension" {
    const allocator = testing.allocator;

    const filename = try output.generateUniqueFilename(allocator, "/path/to/file");
    defer allocator.free(filename);

    // Should append UUID
    try testing.expect(std.mem.indexOf(u8, filename, "/path/to/file-") != null);
    try testing.expect(filename.len > "/path/to/file-".len);
}

test "generateUniqueFilename with null creates temp file path" {
    const allocator = testing.allocator;

    const filename = try output.generateUniqueFilename(allocator, null);
    defer allocator.free(filename);

    // Should be in /tmp and end with .json
    try testing.expect(std.mem.startsWith(u8, filename, "/tmp/stump-"));
    try testing.expect(std.mem.endsWith(u8, filename, ".json"));
}

test "estimateTokenCount converts bytes to tokens" {
    try testing.expectEqual(@as(u64, 250), output.estimateTokenCount(1000));
    try testing.expectEqual(@as(u64, 500), output.estimateTokenCount(2000));
    try testing.expectEqual(@as(u64, 1), output.estimateTokenCount(4));
    try testing.expectEqual(@as(u64, 0), output.estimateTokenCount(3));
}

test "calculateByteLimit converts tokens to bytes" {
    try testing.expectEqual(@as(u64, 4000), output.calculateByteLimit(1000));
    try testing.expectEqual(@as(u64, 40000), output.calculateByteLimit(10000));
    try testing.expectEqual(@as(u64, 400000), output.calculateByteLimit(100000));
}

test "token and byte conversions are reciprocal" {
    const tokens: u64 = 10000;
    const bytes = output.calculateByteLimit(tokens);
    const back_to_tokens = output.estimateTokenCount(bytes);

    try testing.expectEqual(tokens, back_to_tokens);
}

test "JsonWriter init creates writer in stdout mode" {
    const allocator = testing.allocator;

    var writer = try output.JsonWriter.init(allocator, null, 40000);
    defer writer.deinit();

    try testing.expect(writer.file == null);
    try testing.expectEqual(@as(u64, 40000), writer.byte_limit.?);
    try testing.expectEqual(@as(u64, 0), writer.current_bytes);
}

test "JsonWriter init creates writer in file mode" {
    const allocator = testing.allocator;

    var writer = try output.JsonWriter.init(allocator, "output.json", null);
    defer writer.deinit();

    // In file mode, byte_limit should be null
    try testing.expect(writer.byte_limit == null);
}
