const std = @import("std");
const testing = std.testing;
const filter = @import("../../src/filter.zig");
const types = @import("../../src/types.zig");

test "isHidden detects hidden files" {
    try testing.expect(filter.isHidden(".hidden"));
    try testing.expect(filter.isHidden(".git"));
    try testing.expect(filter.isHidden("."));
    try testing.expect(filter.isHidden(".."));
}

test "isHidden returns false for visible files" {
    try testing.expect(!filter.isHidden("visible"));
    try testing.expect(!filter.isHidden("file.txt"));
    try testing.expect(!filter.isHidden(""));
}

test "getExtension extracts extension correctly" {
    try testing.expectEqualStrings("txt", filter.getExtension("file.txt").?);
    try testing.expectEqualStrings("zig", filter.getExtension("main.zig").?);
    try testing.expectEqualStrings("gz", filter.getExtension("archive.tar.gz").?);
}

test "getExtension handles edge cases" {
    try testing.expect(filter.getExtension("no_extension") == null);
    try testing.expect(filter.getExtension(".hidden") == null);
    try testing.expect(filter.getExtension("trailing.") == null);
    try testing.expect(filter.getExtension("") == null);
    try testing.expect(filter.getExtension(".") == null);
}

test "getExtension handles paths with directories" {
    try testing.expectEqualStrings("txt", filter.getExtension("path/to/file.txt").?);
    try testing.expect(filter.getExtension("path/to/noext") == null);
    try testing.expect(filter.getExtension("path/.hidden") == null);
}

test "basename extracts filename from path" {
    try testing.expectEqualStrings("file.txt", filter.basename("path/to/file.txt"));
    try testing.expectEqualStrings("main.zig", filter.basename("/src/main.zig"));
    try testing.expectEqualStrings("file", filter.basename("file"));
    try testing.expectEqualStrings("", filter.basename("path/to/"));
}

test "basename handles empty path" {
    try testing.expectEqualStrings("", filter.basename(""));
}

test "basename handles Windows paths" {
    try testing.expectEqualStrings("file.txt", filter.basename("C:\\path\\to\\file.txt"));
}

test "globMatch exact match" {
    try testing.expect(filter.globMatch("hello", "hello"));
    try testing.expect(filter.globMatch("file.txt", "file.txt"));
    try testing.expect(!filter.globMatch("hello", "world"));
}

test "globMatch with asterisk wildcard" {
    try testing.expect(filter.globMatch("*.txt", "file.txt"));
    try testing.expect(filter.globMatch("*.txt", "document.txt"));
    try testing.expect(!filter.globMatch("*.txt", "file.zig"));

    try testing.expect(filter.globMatch("test*", "test"));
    try testing.expect(filter.globMatch("test*", "testing"));
    try testing.expect(filter.globMatch("test*", "test123"));

    try testing.expect(filter.globMatch("*test*", "testing"));
    try testing.expect(filter.globMatch("*test*", "mytest"));
    try testing.expect(filter.globMatch("*test*", "mytestfile"));
}

test "globMatch with question mark wildcard" {
    try testing.expect(filter.globMatch("file?.txt", "file1.txt"));
    try testing.expect(filter.globMatch("file?.txt", "fileA.txt"));
    try testing.expect(!filter.globMatch("file?.txt", "file12.txt"));
    try testing.expect(!filter.globMatch("file?.txt", "file.txt"));
}

test "globMatch with combined wildcards" {
    try testing.expect(filter.globMatch("test*?.txt", "test123.txt"));
    try testing.expect(filter.globMatch("*file?.txt", "myfile1.txt"));
    try testing.expect(filter.globMatch("*.??g", "file.zig"));
    try testing.expect(filter.globMatch("*.??g", "main.zig"));
}

test "globMatch edge cases" {
    try testing.expect(filter.globMatch("*", "anything"));
    try testing.expect(filter.globMatch("*", ""));
    try testing.expect(filter.globMatch("", ""));
    try testing.expect(!filter.globMatch("", "something"));
}

test "FilterContext.init copies config values" {
    const include = [_][]const u8{ "zig", "txt" };
    const exclude = [_][]const u8{ "log" };
    const patterns = [_][]const u8{ "node_modules" };

    var config = types.Config{
        .path = "test",
        .include_ext = &include,
        .exclude_ext = &exclude,
        .exclude_patterns = &patterns,
        .show_hidden = false,
    };

    const ctx = filter.FilterContext.init(&config);

    try testing.expect(ctx.include_ext != null);
    try testing.expect(ctx.exclude_ext != null);
    try testing.expect(ctx.exclude_patterns != null);
    try testing.expect(!ctx.show_hidden);
}

test "shouldInclude filters hidden files when show_hidden is false" {
    var config = types.Config{
        .path = "test",
        .show_hidden = false,
    };

    const ctx = filter.FilterContext.init(&config);

    try testing.expect(!filter.shouldInclude(&ctx, ".hidden", .file));
    try testing.expect(!filter.shouldInclude(&ctx, ".git", .directory));
    try testing.expect(filter.shouldInclude(&ctx, "visible.txt", .file));
}

test "shouldInclude allows hidden files when show_hidden is true" {
    var config = types.Config{
        .path = "test",
        .show_hidden = true,
    };

    const ctx = filter.FilterContext.init(&config);

    try testing.expect(filter.shouldInclude(&ctx, ".hidden", .file));
    try testing.expect(filter.shouldInclude(&ctx, ".git", .directory));
}

test "shouldInclude applies include_ext filter to files" {
    const include = [_][]const u8{ "zig", "txt" };
    var config = types.Config{
        .path = "test",
        .include_ext = &include,
        .show_hidden = true,
    };

    const ctx = filter.FilterContext.init(&config);

    try testing.expect(filter.shouldInclude(&ctx, "main.zig", .file));
    try testing.expect(filter.shouldInclude(&ctx, "readme.txt", .file));
    try testing.expect(!filter.shouldInclude(&ctx, "script.js", .file));
    try testing.expect(!filter.shouldInclude(&ctx, "noextension", .file));
}

test "shouldInclude does not apply include_ext to directories" {
    const include = [_][]const u8{"zig"};
    var config = types.Config{
        .path = "test",
        .include_ext = &include,
        .show_hidden = true,
    };

    const ctx = filter.FilterContext.init(&config);

    // Directories should always pass extension filters
    try testing.expect(filter.shouldInclude(&ctx, "src", .directory));
    try testing.expect(filter.shouldInclude(&ctx, "test.js", .directory));
}

test "shouldInclude applies exclude_ext filter to files" {
    const exclude = [_][]const u8{ "log", "tmp" };
    var config = types.Config{
        .path = "test",
        .exclude_ext = &exclude,
        .show_hidden = true,
    };

    const ctx = filter.FilterContext.init(&config);

    try testing.expect(filter.shouldInclude(&ctx, "main.zig", .file));
    try testing.expect(!filter.shouldInclude(&ctx, "debug.log", .file));
    try testing.expect(!filter.shouldInclude(&ctx, "cache.tmp", .file));
}

test "shouldInclude applies exclude_patterns with exact match" {
    const patterns = [_][]const u8{"node_modules"};
    var config = types.Config{
        .path = "test",
        .exclude_patterns = &patterns,
        .show_hidden = true,
    };

    const ctx = filter.FilterContext.init(&config);

    try testing.expect(!filter.shouldInclude(&ctx, "project/node_modules", .directory));
    try testing.expect(!filter.shouldInclude(&ctx, "node_modules/lib", .file));
    try testing.expect(filter.shouldInclude(&ctx, "src/main.zig", .file));
}

test "shouldInclude applies exclude_patterns with glob matching" {
    const patterns = [_][]const u8{"*.log"};
    var config = types.Config{
        .path = "test",
        .exclude_patterns = &patterns,
        .show_hidden = true,
    };

    const ctx = filter.FilterContext.init(&config);

    try testing.expect(!filter.shouldInclude(&ctx, "debug.log", .file));
    try testing.expect(!filter.shouldInclude(&ctx, "error.log", .file));
    try testing.expect(filter.shouldInclude(&ctx, "main.zig", .file));
}

test "shouldInclude combines multiple filters" {
    const include = [_][]const u8{"zig"};
    const patterns = [_][]const u8{"test*"};
    var config = types.Config{
        .path = "test",
        .include_ext = &include,
        .exclude_patterns = &patterns,
        .show_hidden = false,
    };

    const ctx = filter.FilterContext.init(&config);

    try testing.expect(filter.shouldInclude(&ctx, "main.zig", .file));
    try testing.expect(!filter.shouldInclude(&ctx, "test_main.zig", .file)); // Excluded by pattern
    try testing.expect(!filter.shouldInclude(&ctx, "main.txt", .file)); // Wrong extension
    try testing.expect(!filter.shouldInclude(&ctx, ".hidden.zig", .file)); // Hidden
}

test "shouldInclude priority: include before exclude for extensions" {
    const include = [_][]const u8{ "zig", "txt" };
    const exclude = [_][]const u8{"zig"}; // Both include and exclude zig
    var config = types.Config{
        .path = "test",
        .include_ext = &include,
        .exclude_ext = &exclude,
        .show_hidden = true,
    };

    const ctx = filter.FilterContext.init(&config);

    // Exclude takes precedence after include
    try testing.expect(!filter.shouldInclude(&ctx, "main.zig", .file));
}
