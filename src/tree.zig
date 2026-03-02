/// Recursive filesystem traversal engine that builds the directory tree.
///
/// Imported by main.zig (executeStump calls buildTree). This is the core
/// algorithm: it walks the filesystem breadth-first from the configured root,
/// applies filters, handles symlinks, enforces safeguards, tracks token limits,
/// and accumulates results into a TraversalState. Delegates to filter.zig for
/// inclusion decisions, symlink.zig for link handling, safeguards.zig for
/// pre-traversal checks, and errors.zig for structured error creation.
const std = @import("std");
const types = @import("types.zig");
const filter = @import("filter.zig");
const symlink = @import("symlink.zig");
const safeguards = @import("safeguards.zig");
const errors = @import("errors.zig");

/// Entry point for directory tree construction.
///
/// Called by main.executeStump after config parsing and performance tracker
/// initialization. Runs the large-directory safeguard check, initializes
/// TraversalState, creates a FilterContext from config, and kicks off recursive
/// traversal from config.dir. Returns the populated state on success, or
/// error.LargeDirectory / error.TokenLimitExceeded for handled failure cases.
pub fn buildTree(allocator: std.mem.Allocator, config: *const types.Config) !types.TraversalState {
    var state = try types.TraversalState.init(allocator, config);
    errdefer state.deinit();

    // Check for large directory before starting traversal
    const safeguard_result = try safeguards.checkLargeDirectory(config.dir, config.force, allocator);
    if (!safeguard_result.isOk()) {
        // Return fatal error - caller should handle this
        return error.LargeDirectory;
    }

    // Initialize filter context
    const filter_ctx = filter.FilterContext.init(config);

    // Start traversal from root directory
    try traverseDirectory(
        &state,
        config.dir,
        "",
        0,
        &filter_ctx,
    );

    return state;
}

/// Recursive core: opens a directory, adds it to the tree, and processes each child.
///
/// Respects the depth limit from Config. On directory-open failure (permissions,
/// etc.), records a non-fatal error and returns without descending. Delegates
/// individual entry processing to processEntry.
fn traverseDirectory(
    state: *types.TraversalState,
    full_path: []const u8,
    relative_path: []const u8,
    current_depth: i32,
    filter_ctx: *const filter.FilterContext,
) anyerror!void {
    // Check depth limit
    if (state.config.depth >= 0 and current_depth > state.config.depth) {
        return;
    }

    // Track performance metrics
    if (state.config.performance) {
        state.performance.readdir_calls += 1;
    }

    // Open directory
    var dir = std.fs.cwd().openDir(full_path, .{ .iterate = true }) catch |err| {
        // Handle non-fatal directory open errors
        try handleDirectoryOpenError(state, relative_path, err);
        return;
    };
    defer dir.close();

    // Add directory entry if not root
    if (relative_path.len > 0) {
        try addDirectoryEntry(state, relative_path, full_path);
    }

    // Iterate over directory entries
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        try processEntry(
            state,
            dir,
            full_path,
            relative_path,
            entry,
            current_depth,
            filter_ctx,
        );
    }
}

/// Processes one filesystem entry: validates UTF-8, builds paths, handles symlinks,
/// applies filters, and dispatches to addFileEntry/traverseDirectory by type.
///
/// This is the per-entry hot path. The order of operations matters: UTF-8
/// validation runs first (to avoid constructing invalid paths), then symlink
/// handling, then filtering, then type-based dispatch.
fn processEntry(
    state: *types.TraversalState,
    parent_dir: std.fs.Dir,
    parent_full_path: []const u8,
    parent_relative_path: []const u8,
    entry: std.fs.Dir.Entry,
    current_depth: i32,
    filter_ctx: *const filter.FilterContext,
) !void {
    // Validate UTF-8 encoding of filename
    if (!safeguards.isValidUtf8(entry.name)) {
        try handleInvalidUtf8(state, parent_relative_path, entry.name);
        return;
    }

    // Build full and relative paths
    var full_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const full_path = try std.fmt.bufPrint(&full_path_buf, "{s}" ++ std.fs.path.sep_str ++ "{s}", .{ parent_full_path, entry.name });

    var relative_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const relative_path = if (parent_relative_path.len > 0)
        try std.fmt.bufPrint(&relative_path_buf, "{s}" ++ std.fs.path.sep_str ++ "{s}", .{ parent_relative_path, entry.name })
    else
        try std.fmt.bufPrint(&relative_path_buf, "{s}", .{entry.name});

    // Track performance metrics
    if (state.config.performance) {
        state.performance.stat_calls += 1;
    }

    // Handle symlinks
    if (entry.kind == .sym_link) {
        const should_skip = try handleSymlink(state, full_path, relative_path);
        if (should_skip) {
            return;
        }
    }

    // Determine entry type for filtering
    const entry_type: types.EntryType = if (entry.kind == .directory) .directory else .file;

    // Apply filters
    if (!filter.shouldInclude(filter_ctx, relative_path, entry_type)) {
        state.stats.filtered += 1;
        return;
    }

    // Process based on entry type
    switch (entry.kind) {
        .file => {
            try addFileEntry(state, relative_path, full_path);
        },
        .directory => {
            // Recursively traverse subdirectory
            try traverseDirectory(
                state,
                full_path,
                relative_path,
                current_depth + 1,
                filter_ctx,
            );
        },
        .sym_link => {
            // If we got here, it means follow_symlinks is true and no cycle was detected
            // Get the actual type after resolving the symlink
            const stat_info = parent_dir.statFile(entry.name) catch |err| {
                try handleStatError(state, relative_path, err);
                return;
            };

            if (stat_info.kind == .directory) {
                // Mark as visited before traversing
                if (state.visited_paths) |*visited| {
                    try symlink.markVisited(visited, full_path);
                }

                try traverseDirectory(
                    state,
                    full_path,
                    relative_path,
                    current_depth + 1,
                    filter_ctx,
                );
            } else {
                try addFileEntry(state, relative_path, full_path);
            }
        },
        else => {
            // Skip other types (block devices, character devices, etc.)
        },
    }
}

/// Dispatches symlink handling based on the follow_symlinks config flag.
///
/// When not following: delegates to symlink.detectSymlink (record and skip).
/// When following: delegates to symlink.handleSymlinkFollow (cycle check).
/// Returns true if the entry should be skipped (symlink recorded or cycle
/// detected with force mode), false to continue normal processing.
fn handleSymlink(state: *types.TraversalState, full_path: []const u8, relative_path: []const u8) !bool {
    // If not following symlinks, detect and record
    if (!state.config.follow_symlinks) {
        return try symlink.detectSymlink(state, full_path, relative_path);
    }

    // If following symlinks, check for cycles
    const should_skip = symlink.handleSymlinkFollow(state, full_path, relative_path) catch |err| {
        if (err == error.SymlinkCycle) {
            // Fatal error if force: false
            if (!state.config.force) {
                return err;
            }
            // With force: true, error is already recorded in handleSymlinkFollow
            return true; // Skip this symlink
        }
        return err;
    };

    return should_skip;
}

/// Handle invalid UTF-8 filename
fn handleInvalidUtf8(state: *types.TraversalState, parent_path: []const u8, filename: []const u8) !void {
    // Build the relative path
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const relative_path = if (parent_path.len > 0)
        try std.fmt.bufPrint(&path_buf, "{s}" ++ std.fs.path.sep_str ++ "{s}", .{ parent_path, filename })
    else
        try std.fmt.bufPrint(&path_buf, "{s}", .{filename});

    if (!state.config.force) {
        // Fatal error - propagate to caller
        return error.NonUtf8Filename;
    }

    // With force: true, record as non-fatal error and skip
    const path_copy = try state.allocator.dupe(u8, relative_path);
    const msg = try state.allocator.dupe(u8, "Invalid UTF-8 encoding in filename");
    const error_entry = types.ErrorEntry.init(.non_utf8_filename, path_copy, msg);
    try state.errors.append(state.allocator, error_entry);
}

/// Add a directory entry to the tree
fn addDirectoryEntry(state: *types.TraversalState, relative_path: []const u8, full_path: []const u8) !void {
    const path_copy = try state.allocator.dupe(u8, relative_path);
    errdefer state.allocator.free(path_copy);

    const modified: ?i128 = if (state.config.show_modified) blk: {
        const stat_info = std.fs.cwd().statFile(full_path) catch break :blk null;
        if (state.config.performance) {
            state.performance.stat_calls += 1;
        }
        break :blk stat_info.mtime;
    } else null;

    const entry = types.TreeEntry{
        .path = path_copy,
        .type = .directory,
        .size = null,
        .modified = modified,
    };

    try state.tree_entries.append(state.allocator, entry);
    state.stats.dirs += 1;

    // Check token limit in stdout mode
    if (state.config.output_file == null) {
        try checkTokenLimit(state);
    }
}

/// Add a file entry to the tree
fn addFileEntry(state: *types.TraversalState, relative_path: []const u8, full_path: []const u8) !void {
    const path_copy = try state.allocator.dupe(u8, relative_path);
    errdefer state.allocator.free(path_copy);

    // Get file metadata if requested
    const need_stat = state.config.show_size or state.config.show_modified;
    const stat_info: ?std.fs.File.Stat = if (need_stat) blk: {
        break :blk std.fs.cwd().statFile(full_path) catch |err| {
            state.allocator.free(path_copy);
            try handleStatError(state, relative_path, err);
            return;
        };
    } else null;

    if (need_stat and state.config.performance) {
        state.performance.stat_calls += 1;
    }

    const size = if (state.config.show_size) blk: {
        break :blk if (stat_info) |si| si.size else null;
    } else null;

    const modified = if (state.config.show_modified) blk: {
        break :blk if (stat_info) |si| si.mtime else null;
    } else null;

    const entry = types.TreeEntry{
        .path = path_copy,
        .type = .file,
        .size = size,
        .modified = modified,
    };

    try state.tree_entries.append(state.allocator, entry);
    state.stats.files += 1;

    // Check token limit in stdout mode
    if (state.config.output_file == null) {
        try checkTokenLimit(state);
    }
}

/// Estimates current output size and aborts traversal if the token limit is exceeded.
///
/// Called after every addDirectoryEntry and addFileEntry when output_file is
/// null (stdout mode). Uses a rough heuristic of path bytes + 50 bytes JSON
/// overhead per entry. Returns error.TokenLimitExceeded which propagates up
/// to main.executeStump for error response generation.
fn checkTokenLimit(state: *types.TraversalState) !void {
    // Estimate current byte count (rough approximation)
    // Each entry is approximately: path length + 50 bytes for JSON overhead
    const estimated_bytes_per_entry: u64 = 50;
    const total_entries = state.stats.dirs + state.stats.files;
    const estimated_bytes = total_entries * estimated_bytes_per_entry;

    // Add estimated bytes for all paths
    var path_bytes: u64 = 0;
    for (state.tree_entries.items) |entry| {
        path_bytes += entry.path.len;
    }

    state.current_byte_count = estimated_bytes + path_bytes;

    if (state.current_byte_count > state.config.resolved_byte_limit) {
        return error.TokenLimitExceeded;
    }
}

/// Handle directory open errors
fn handleDirectoryOpenError(state: *types.TraversalState, path: []const u8, err: anyerror) !void {
    const path_copy = try state.allocator.dupe(u8, path);

    const error_entry = switch (err) {
        error.AccessDenied => try errors.createPermissionDeniedError(state.allocator, path_copy),
        error.NameTooLong => try errors.createPathTooLongError(state.allocator, path_copy),
        else => blk: {
            const msg = try std.fmt.allocPrint(state.allocator, "Cannot open directory: {s}", .{@errorName(err)});
            break :blk types.ErrorEntry.init(.unknown_error, path_copy, msg);
        },
    };

    try state.errors.append(state.allocator, error_entry);
}

/// Handle stat errors
fn handleStatError(state: *types.TraversalState, path: []const u8, err: anyerror) !void {
    const path_copy = try state.allocator.dupe(u8, path);

    const error_entry = switch (err) {
        error.AccessDenied => try errors.createPermissionDeniedError(state.allocator, path_copy),
        error.NameTooLong => try errors.createPathTooLongError(state.allocator, path_copy),
        else => try errors.createUnreadableFileError(state.allocator, path_copy),
    };

    try state.errors.append(state.allocator, error_entry);
}
