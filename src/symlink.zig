const std = @import("std");
const types = @import("types.zig");
const errors = @import("errors.zig");

/// Check if a path is a symbolic link
pub fn isSymlink(path: []const u8) !bool {
    const stat_info = std.fs.cwd().statFile(path) catch |err| {
        return switch (err) {
            error.FileNotFound => false,
            else => err,
        };
    };
    return stat_info.kind == .sym_link;
}

/// Resolve symbolic link target
/// Caller owns returned memory
pub fn resolveTarget(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    // Use readlink to get the target path
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const target = try std.fs.cwd().readLink(path, &buf);
    return try allocator.dupe(u8, target);
}

/// Get device and inode for a path (for cycle detection)
pub fn getDeviceInode(path: []const u8) !types.VisitedPath {
    const stat_info = try std.posix.fstatat(std.posix.AT.FDCWD, path, 0);
    return types.VisitedPath{
        .dev = @intCast(stat_info.dev),
        .ino = @intCast(stat_info.ino),
    };
}

/// Check if a path has been visited (cycle detection)
pub fn isVisited(visited_paths: *std.AutoHashMap(types.VisitedPath, void), path: []const u8) !bool {
    const visited_path = try getDeviceInode(path);
    return visited_paths.contains(visited_path);
}

/// Mark a path as visited (cycle detection)
pub fn markVisited(visited_paths: *std.AutoHashMap(types.VisitedPath, void), path: []const u8) !void {
    const visited_path = try getDeviceInode(path);
    try visited_paths.put(visited_path, {});
}

/// Handle symlink detection (when follow_symlinks: false)
/// Records symlink info and returns true if symlink should be skipped
pub fn detectSymlink(
    state: *types.TraversalState,
    path: []const u8,
    relative_path: []const u8,
) !bool {
    const is_link = try isSymlink(path);
    if (!is_link) {
        return false;
    }

    // Track symlink count
    state.stats.symlinks += 1;

    // If not following symlinks, record and skip
    if (!state.config.follow_symlinks) {
        const target = resolveTarget(state.allocator, path) catch {
            // Broken symlink - record as error
            const path_copy = try state.allocator.dupe(u8, relative_path);
            const error_entry = try errors.createInvalidSymlinkError(
                state.allocator,
                path_copy,
                "",
            );
            try state.errors.append(state.allocator, error_entry);
            return true; // Skip this symlink
        };
        errdefer state.allocator.free(target);

        const path_copy = try state.allocator.dupe(u8, relative_path);
        errdefer state.allocator.free(path_copy);

        const symlink_info = types.SymlinkInfo{
            .path = path_copy,
            .target = target,
        };

        try state.symlinks.append(state.allocator, symlink_info);
        return true; // Skip traversal of this symlink
    }

    return false; // Continue to cycle detection
}

/// Handle symlink following with cycle detection (when follow_symlinks: true)
/// Returns error if cycle detected and force: false
/// Returns true if symlink should be skipped (cycle with force: true or broken link)
pub fn handleSymlinkFollow(
    state: *types.TraversalState,
    path: []const u8,
    relative_path: []const u8,
) !bool {
    if (!state.config.follow_symlinks) {
        return false;
    }

    const is_link = try isSymlink(path);
    if (!is_link) {
        return false;
    }

    // Track symlink resolution in performance metrics
    if (state.config.performance) {
        state.performance.symlink_resolutions += 1;
    }

    // Resolve the target to get its canonical path
    const target = resolveTarget(state.allocator, path) catch {
        // Broken symlink - record as non-fatal error and skip
        const path_copy = try state.allocator.dupe(u8, relative_path);
        const error_entry = try errors.createInvalidSymlinkError(
            state.allocator,
            path_copy,
            "",
        );
        try state.errors.append(state.allocator, error_entry);
        return true; // Skip this symlink
    };
    defer state.allocator.free(target);

    // Build the full path to the target (handle relative symlinks)
    var target_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const target_path = if (std.fs.path.isAbsolute(target)) blk: {
        break :blk target;
    } else blk: {
        // Relative symlink - resolve relative to parent directory of the link
        const parent_dir = std.fs.path.dirname(path) orelse ".";
        const joined = try std.fmt.bufPrint(&target_path_buf, "{s}/{s}", .{ parent_dir, target });
        break :blk joined;
    };

    // Check if we've already visited this target (cycle detection)
    if (state.visited_paths) |*visited| {
        const already_visited = try isVisited(visited, target_path);
        if (already_visited) {
            // Cycle detected
            if (!state.config.force) {
                // Fatal error - return error to abort
                return error.SymlinkCycle;
            }

            // With force: true, record as non-fatal error and skip
            const path_copy = try state.allocator.dupe(u8, relative_path);
            const target_copy = try state.allocator.dupe(u8, target);
            const msg = try std.fmt.allocPrint(
                state.allocator,
                "Symlink cycle detected: {s} -> {s}",
                .{ relative_path, target },
            );
            const error_entry = types.ErrorEntry.initWithTarget(
                .symlink_cycle,
                path_copy,
                target_copy,
                msg,
            );
            try state.errors.append(state.allocator, error_entry);
            return true; // Skip this symlink
        }

        // Mark as visited to detect future cycles
        try markVisited(visited, target_path);
    }

    return false; // Continue traversal through this symlink
}

/// Track symlink in symlinks_detected array (when follow_symlinks: false)
/// This is a convenience function used by tree.zig
pub fn trackSymlink(
    state: *types.TraversalState,
    relative_path: []const u8,
    full_path: []const u8,
) !void {
    const target = try resolveTarget(state.allocator, full_path);
    errdefer state.allocator.free(target);

    const path_copy = try state.allocator.dupe(u8, relative_path);
    errdefer state.allocator.free(path_copy);

    const symlink_info = types.SymlinkInfo{
        .path = path_copy,
        .target = target,
    };

    try state.symlinks.append(state.allocator, symlink_info);
    state.stats.symlinks += 1;
}

/// Check if target exists (for validating symlinks)
pub fn targetExists(target_path: []const u8) bool {
    std.fs.cwd().access(target_path, .{}) catch {
        return false;
    };
    return true;
}

/// Get the canonical path of a symlink target
/// This resolves all symlinks in the path to get the final destination
/// Caller owns returned memory
pub fn getCanonicalPath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const real_path = try std.fs.cwd().realpath(path, &buf);
    return try allocator.dupe(u8, real_path);
}
