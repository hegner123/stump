/// Entry filtering logic applied during directory traversal.
///
/// Imported by tree.zig to decide whether each filesystem entry should be
/// included in the output tree. Supports hidden-file filtering, extension
/// include/exclude lists, and glob-based path exclusion patterns. All filter
/// state is read-only after initialization from the Config.
const std = @import("std");
const types = @import("types.zig");

/// Immutable snapshot of filter rules extracted from Config.
///
/// Created by tree.buildTree before traversal begins, then passed by
/// pointer through traverseDirectory and processEntry. Avoids repeatedly
/// accessing the full Config struct during the hot path.
pub const FilterContext = struct {
    include_ext: ?[]const []const u8,
    exclude_ext: ?[]const []const u8,
    exclude_patterns: ?[]const []const u8,
    show_hidden: bool,

    pub fn init(config: *const types.Config) FilterContext {
        return .{
            .include_ext = config.include_ext,
            .exclude_ext = config.exclude_ext,
            .exclude_patterns = config.exclude_patterns,
            .show_hidden = config.show_hidden,
        };
    }
};

/// Check if a filename is hidden (starts with '.')
pub fn isHidden(name: []const u8) bool {
    if (name.len == 0) return false;
    return name[0] == '.';
}

/// Extract file extension from a path
/// Returns null if no extension found
pub fn getExtension(path: []const u8) ?[]const u8 {
    if (path.len == 0) return null;

    // Find last dot
    var i: usize = path.len;
    while (i > 0) {
        i -= 1;
        if (path[i] == '.') {
            // Don't treat leading dot as extension (hidden files)
            if (i == 0) return null;
            // Don't treat trailing dot as extension
            if (i == path.len - 1) return null;
            // Return extension without the dot
            return path[i + 1 ..];
        }
        // Stop at path separator
        if (path[i] == '/' or path[i] == '\\') {
            return null;
        }
    }

    return null;
}

/// Check if extension matches any in the list
fn extensionMatches(ext: []const u8, ext_list: []const []const u8) bool {
    for (ext_list) |target_ext| {
        if (std.mem.eql(u8, ext, target_ext)) {
            return true;
        }
    }
    return false;
}

/// Recursive glob pattern matcher supporting '*' (any sequence) and '?' (single char).
///
/// Used by matchesExcludePattern when an exclude pattern contains wildcard
/// characters. Operates on the full relative path, not just the filename.
/// Note: does not support '**' (multi-directory) or character classes.
pub fn globMatch(pattern: []const u8, str: []const u8) bool {
    return globMatchImpl(pattern, str, 0, 0);
}

fn globMatchImpl(pattern: []const u8, str: []const u8, p_idx: usize, s_idx: usize) bool {
    // Both exhausted - match
    if (p_idx >= pattern.len and s_idx >= str.len) {
        return true;
    }

    // Pattern exhausted but string remains - no match
    if (p_idx >= pattern.len) {
        return false;
    }

    // Handle '*' wildcard
    if (pattern[p_idx] == '*') {
        // Try matching zero characters
        if (globMatchImpl(pattern, str, p_idx + 1, s_idx)) {
            return true;
        }
        // Try matching one or more characters
        if (s_idx < str.len) {
            return globMatchImpl(pattern, str, p_idx, s_idx + 1);
        }
        return false;
    }

    // String exhausted but pattern has non-wildcard - no match
    if (s_idx >= str.len) {
        return false;
    }

    // Handle '?' single character wildcard
    if (pattern[p_idx] == '?') {
        return globMatchImpl(pattern, str, p_idx + 1, s_idx + 1);
    }

    // Exact character match
    if (pattern[p_idx] == str[s_idx]) {
        return globMatchImpl(pattern, str, p_idx + 1, s_idx + 1);
    }

    // No match
    return false;
}

/// Check if path matches any exclude pattern
fn matchesExcludePattern(path: []const u8, patterns: []const []const u8) bool {
    for (patterns) |pattern| {
        // Check if pattern contains wildcards
        const has_wildcard = std.mem.indexOfAny(u8, pattern, "*?") != null;

        if (has_wildcard) {
            // Glob matching
            if (globMatch(pattern, path)) {
                return true;
            }
        } else {
            // Exact substring match
            if (std.mem.indexOf(u8, path, pattern) != null) {
                return true;
            }
        }
    }
    return false;
}

/// Get the basename (filename) from a path
pub fn basename(path: []const u8) []const u8 {
    if (path.len == 0) return path;

    // Find last separator
    var i: usize = path.len;
    while (i > 0) {
        i -= 1;
        if (path[i] == '/' or path[i] == '\\') {
            return path[i + 1 ..];
        }
    }

    return path;
}

/// Central filter gate called for every entry in tree.processEntry.
///
/// Applies filters in order: hidden files, exclude patterns (glob or substring),
/// then extension include/exclude lists. Extension filters only apply to files --
/// directories always pass the extension check. Returns false to filter out
/// the entry (incrementing stats.filtered in tree.processEntry).
pub fn shouldInclude(ctx: *const FilterContext, path: []const u8, entry_type: types.EntryType) bool {
    const name = basename(path);

    // Filter 1: Hidden files (unless show_hidden is true)
    if (!ctx.show_hidden and isHidden(name)) {
        return false;
    }

    // Filter 2: Exclude patterns (apply to full path)
    if (ctx.exclude_patterns) |patterns| {
        if (matchesExcludePattern(path, patterns)) {
            return false;
        }
    }

    // Filter 3: Extension filtering (only applies to files)
    if (entry_type == .file) {
        if (getExtension(name)) |ext| {
            // If include_ext is specified, file must match
            if (ctx.include_ext) |include_list| {
                if (!extensionMatches(ext, include_list)) {
                    return false;
                }
            }

            // If exclude_ext is specified, file must not match
            if (ctx.exclude_ext) |exclude_list| {
                if (extensionMatches(ext, exclude_list)) {
                    return false;
                }
            }
        } else {
            // File has no extension
            // If include_ext is specified, file without extension is excluded
            if (ctx.include_ext) |_| {
                return false;
            }
        }
    }

    // Passed all filters
    return true;
}

/// Optional statistics for measuring how many entries the filter removes.
///
/// Not currently used during normal traversal -- the main stats.filtered
/// counter in TraversalState serves that purpose. The efficiency percentage
/// is consumed by PerformanceTracker.finalize when performance mode is on.
pub const FilterStats = struct {
    total_checked: u64 = 0,
    filtered_out: u64 = 0,

    pub fn efficiency(self: FilterStats) f64 {
        if (self.total_checked == 0) return 0.0;
        return (@as(f64, @floatFromInt(self.filtered_out)) / @as(f64, @floatFromInt(self.total_checked))) * 100.0;
    }

    pub fn recordChecked(self: *FilterStats) void {
        self.total_checked += 1;
    }

    pub fn recordFiltered(self: *FilterStats) void {
        self.filtered_out += 1;
    }
};

// Tests
test "isHidden" {
    try std.testing.expect(isHidden(".git"));
    try std.testing.expect(isHidden(".hidden"));
    try std.testing.expect(!isHidden("visible"));
    try std.testing.expect(!isHidden(""));
}

test "getExtension" {
    try std.testing.expectEqualStrings("txt", getExtension("file.txt").?);
    try std.testing.expectEqualStrings("zig", getExtension("main.zig").?);
    try std.testing.expectEqualStrings("zig", getExtension("src/main.zig").?);
    try std.testing.expectEqualStrings("tar.gz", getExtension("archive.tar.gz").?);
    try std.testing.expect(getExtension("noext") == null);
    try std.testing.expect(getExtension(".hidden") == null);
    try std.testing.expect(getExtension("trailing.") == null);
    try std.testing.expect(getExtension("") == null);
}

test "basename" {
    try std.testing.expectEqualStrings("file.txt", basename("file.txt"));
    try std.testing.expectEqualStrings("file.txt", basename("dir/file.txt"));
    try std.testing.expectEqualStrings("file.txt", basename("/path/to/file.txt"));
    try std.testing.expectEqualStrings("", basename(""));
}

test "globMatch basic" {
    // Exact match
    try std.testing.expect(globMatch("test", "test"));
    try std.testing.expect(!globMatch("test", "other"));

    // Wildcard *
    try std.testing.expect(globMatch("*.txt", "file.txt"));
    try std.testing.expect(globMatch("*.txt", "my.file.txt"));
    try std.testing.expect(!globMatch("*.txt", "file.md"));
    try std.testing.expect(globMatch("test*", "test"));
    try std.testing.expect(globMatch("test*", "test123"));
    try std.testing.expect(globMatch("*test", "mytest"));

    // Wildcard ?
    try std.testing.expect(globMatch("test?", "test1"));
    try std.testing.expect(globMatch("?est", "test"));
    try std.testing.expect(!globMatch("test?", "test12"));

    // Combined
    try std.testing.expect(globMatch("t*t?", "test1"));
    try std.testing.expect(globMatch("*.???", "file.txt"));
}

test "shouldInclude hidden files" {
    const allocator = std.testing.allocator;

    var config = types.Config{
        .dir = try allocator.dupe(u8, "/test"),
        .show_hidden = false,
    };
    defer config.deinit(allocator);

    const ctx = FilterContext.init(&config);

    try std.testing.expect(!shouldInclude(&ctx, ".git/config", .file));
    try std.testing.expect(!shouldInclude(&ctx, ".hidden", .file));
    try std.testing.expect(shouldInclude(&ctx, "visible.txt", .file));

    config.show_hidden = true;
    const ctx2 = FilterContext.init(&config);
    try std.testing.expect(shouldInclude(&ctx2, ".git/config", .file));
}

test "shouldInclude extensions" {
    const allocator = std.testing.allocator;

    // Test include_ext
    const include_exts = try allocator.alloc([]const u8, 2);
    include_exts[0] = try allocator.dupe(u8, "zig");
    include_exts[1] = try allocator.dupe(u8, "txt");

    var config = types.Config{
        .dir = try allocator.dupe(u8, "/test"),
        .include_ext = include_exts,
    };
    defer config.deinit(allocator);

    const ctx = FilterContext.init(&config);

    try std.testing.expect(shouldInclude(&ctx, "main.zig", .file));
    try std.testing.expect(shouldInclude(&ctx, "readme.txt", .file));
    try std.testing.expect(!shouldInclude(&ctx, "build.md", .file));
    try std.testing.expect(!shouldInclude(&ctx, "noext", .file));

    // Directories should pass through
    try std.testing.expect(shouldInclude(&ctx, "src", .directory));
}

test "shouldInclude exclude extensions" {
    const allocator = std.testing.allocator;

    const exclude_exts = try allocator.alloc([]const u8, 2);
    exclude_exts[0] = try allocator.dupe(u8, "log");
    exclude_exts[1] = try allocator.dupe(u8, "tmp");

    var config = types.Config{
        .dir = try allocator.dupe(u8, "/test"),
        .exclude_ext = exclude_exts,
    };
    defer config.deinit(allocator);

    const ctx = FilterContext.init(&config);

    try std.testing.expect(!shouldInclude(&ctx, "debug.log", .file));
    try std.testing.expect(!shouldInclude(&ctx, "cache.tmp", .file));
    try std.testing.expect(shouldInclude(&ctx, "main.zig", .file));
}

test "shouldInclude exclude patterns" {
    const allocator = std.testing.allocator;

    const patterns = try allocator.alloc([]const u8, 2);
    patterns[0] = try allocator.dupe(u8, "*.log");
    patterns[1] = try allocator.dupe(u8, "node_modules");

    var config = types.Config{
        .dir = try allocator.dupe(u8, "/test"),
        .exclude_patterns = patterns,
    };
    defer config.deinit(allocator);

    const ctx = FilterContext.init(&config);

    try std.testing.expect(!shouldInclude(&ctx, "debug.log", .file));
    try std.testing.expect(!shouldInclude(&ctx, "src/node_modules/pkg/file.js", .file));
    try std.testing.expect(shouldInclude(&ctx, "src/main.zig", .file));
}

test "FilterStats efficiency" {
    var stats = FilterStats{};

    stats.recordChecked();
    stats.recordChecked();
    stats.recordChecked();
    stats.recordChecked();
    stats.recordFiltered();
    stats.recordFiltered();

    try std.testing.expectEqual(@as(u64, 4), stats.total_checked);
    try std.testing.expectEqual(@as(u64, 2), stats.filtered_out);
    try std.testing.expectApproxEqAbs(@as(f64, 50.0), stats.efficiency(), 0.01);
}
