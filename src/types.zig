/// Core data types for the stump directory tree tool.
///
/// Defines all shared structs, enums, and state containers used across the
/// codebase. Imported by every other module in the project. No module-level
/// logic -- purely type definitions and their associated methods.
const std = @import("std");

/// Filesystem entry classification used throughout traversal and serialization.
///
/// Assigned in tree.zig during directory walking. Consumed by filter.zig to
/// apply extension-based filtering (only files have extensions), and by
/// output.zig to emit the single-character type code ("f", "d", "s") in JSON.
pub const EntryType = enum {
    file,
    directory,
    symlink,

    pub fn toChar(self: EntryType) u8 {
        return switch (self) {
            .file => 'f',
            .directory => 'd',
            .symlink => 's',
        };
    }

    pub fn toString(self: EntryType) []const u8 {
        return switch (self) {
            .file => "f",
            .directory => "d",
            .symlink => "s",
        };
    }
};

/// Single node in the output tree, representing one file, directory, or symlink.
///
/// Created by tree.addFileEntry and tree.addDirectoryEntry during traversal.
/// Collected into TraversalState.tree_entries, then serialized by output.writeJson.
/// The path is relative to the scan root directory.
pub const TreeEntry = struct {
    path: []const u8,
    type: EntryType,
    size: ?u64 = null, // Only for files, optional
    modified: ?i128 = null, // Unix timestamp in nanoseconds, optional

    pub fn deinit(self: *TreeEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
    }
};

/// Recorded symlink with its resolved target path.
///
/// Created by symlink.detectSymlink when follow_symlinks is false. Collected
/// into TraversalState.symlinks and serialized in the "symlinks_detected"
/// JSON array by output.writeJson. Not populated when following symlinks.
pub const SymlinkInfo = struct {
    path: []const u8,
    target: []const u8,

    pub fn deinit(self: *SymlinkInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        allocator.free(self.target);
    }
};

/// Categorizes errors encountered during traversal into fatal and non-fatal.
///
/// Fatal errors (large_directory, non_utf8_filename, symlink_cycle) halt
/// execution unless force mode is enabled. Non-fatal errors are collected
/// into TraversalState.errors and reported in the output JSON. Created by
/// errors.zig factory functions, consumed by output.zig during serialization.
pub const ErrorType = enum {
    // Fatal errors (block execution unless force: true)
    large_directory,
    non_utf8_filename,
    symlink_cycle,

    // Non-fatal errors (collected and reported)
    permission_denied,
    invalid_symlink,
    path_too_long,
    unreadable_file,
    token_limit_exceeded,
    invalid_input,
    unknown_error,

    pub fn isFatal(self: ErrorType) bool {
        return switch (self) {
            .large_directory, .non_utf8_filename, .symlink_cycle => true,
            else => false,
        };
    }

    pub fn toString(self: ErrorType) []const u8 {
        return switch (self) {
            .large_directory => "large_directory",
            .non_utf8_filename => "non_utf8_filename",
            .symlink_cycle => "symlink_cycle",
            .permission_denied => "permission_denied",
            .invalid_symlink => "invalid_symlink",
            .path_too_long => "path_too_long",
            .unreadable_file => "unreadable_file",
            .token_limit_exceeded => "token_limit_exceeded",
            .invalid_input => "invalid_input",
            .unknown_error => "unknown_error",
        };
    }
};

/// A non-fatal error encountered during traversal that did not halt execution.
///
/// Created by errors.zig factory functions (createPermissionDeniedError, etc.)
/// and by tree.zig error handlers. Collected in TraversalState.errors and
/// serialized in the "errors" JSON array by output.writeJson.
/// All string fields are owned and must be freed via deinit.
pub const ErrorEntry = struct {
    type: ErrorType,
    path: []const u8,
    message: []const u8,
    target: ?[]const u8 = null, // Only for symlink-related errors

    pub fn init(err_type: ErrorType, path: []const u8, message: []const u8) ErrorEntry {
        return .{
            .type = err_type,
            .path = path,
            .message = message,
        };
    }

    pub fn initWithTarget(err_type: ErrorType, path: []const u8, target: []const u8, message: []const u8) ErrorEntry {
        return .{
            .type = err_type,
            .path = path,
            .message = message,
            .target = target,
        };
    }

    pub fn initAlloc(err_type: ErrorType, path: []const u8, message: []const u8, allocator: std.mem.Allocator) !ErrorEntry {
        const path_copy = try allocator.dupe(u8, path);
        const msg_copy = try allocator.dupe(u8, message);
        return .{
            .type = err_type,
            .path = path_copy,
            .message = msg_copy,
        };
    }

    pub fn deinit(self: *ErrorEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        allocator.free(self.message);
        if (self.target) |t| {
            allocator.free(t);
        }
    }
};

/// Counters accumulated during traversal, included in every output JSON.
///
/// Incremented by tree.addFileEntry, tree.addDirectoryEntry, and
/// symlink.detectSymlink. Serialized by output.writeJson into the "stats"
/// object. The aborted_at and token_limit fields are only populated when
/// the token limit is exceeded during stdout-mode output.
pub const Stats = struct {
    dirs: u64 = 0,
    files: u64 = 0,
    filtered: u64 = 0,
    symlinks: u64 = 0,
    aborted_at: ?u64 = null, // Only set when token limit exceeded
    token_limit: ?u64 = null, // Only set when token limit exceeded
};

/// Detailed execution metrics, only populated when Config.performance is true.
///
/// Computed by PerformanceTracker.finalize in performance.zig at the end of
/// execution. Stored in OutputData.performance and serialized by output.writeJson
/// into the optional "performance" JSON object.
pub const PerformanceMetrics = struct {
    // Execution time (milliseconds)
    total_ms: u64 = 0,
    traversal_ms: u64 = 0,
    filtering_ms: u64 = 0,
    serialization_ms: u64 = 0,

    // Memory consumption
    peak_memory_bytes: u64 = 0,
    final_memory_bytes: u64 = 0,
    allocations: u64 = 0,

    // Filesystem operations
    stat_calls: u64 = 0,
    readdir_calls: u64 = 0,
    symlink_resolutions: u64 = 0,

    // Processing metrics
    items_per_second: u64 = 0,
    bytes_per_second: u64 = 0,
    avg_time_per_item_us: u64 = 0,

    // Efficiency metrics
    filter_efficiency: f64 = 0.0,
    cache_hits: u64 = 0,
};

/// Tree entry sort order. Currently only .none is used in the codebase;
/// the other variants are defined for future use.
pub const SortOption = enum {
    none,
    name,
    size,
    type_then_name,
};

/// Configuration for a single tree traversal operation.
///
/// Constructed by main.parseCliArgs (CLI mode) or main.parseConfig (MCP mode).
/// Passed to tree.buildTree to control traversal behavior. The resolved_token_limit
/// and resolved_byte_limit fields are computed by config.resolveTokenLimit after
/// merging the explicit parameter, STUMP_TOKEN_LIMIT env var, and default.
pub const Config = struct {
    // Input parameters
    dir: []const u8,
    depth: i32 = -1, // -1 means unlimited
    include_ext: ?[]const []const u8 = null,
    exclude_ext: ?[]const []const u8 = null,
    exclude_patterns: ?[]const []const u8 = null,
    show_hidden: bool = true,
    show_size: bool = true,
    show_modified: bool = false,
    follow_symlinks: bool = false,
    force: bool = false,
    performance: bool = false,
    output_file: ?[]const u8 = null,
    token_limit: ?u64 = null,
    sort: SortOption = .none,

    // Resolved token limit (after checking env var and clamping)
    resolved_token_limit: u64 = 10000,
    resolved_byte_limit: u64 = 40000, // resolved_token_limit * 4

    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        allocator.free(self.dir);
        if (self.include_ext) |ext_list| {
            for (ext_list) |ext| {
                allocator.free(ext);
            }
            allocator.free(ext_list);
        }
        if (self.exclude_ext) |ext_list| {
            for (ext_list) |ext| {
                allocator.free(ext);
            }
            allocator.free(ext_list);
        }
        if (self.exclude_patterns) |pattern_list| {
            for (pattern_list) |pattern| {
                allocator.free(pattern);
            }
            allocator.free(pattern_list);
        }
        if (self.output_file) |file| {
            allocator.free(file);
        }
    }
};

/// Complete output payload assembled from traversal results before serialization.
///
/// Built by main.buildOutputData from TraversalState after traversal completes.
/// Passed to output.serializeToStdout or output.serializeToFile for JSON encoding.
/// Borrows tree entries, symlinks, and errors from TraversalState -- only root
/// and _note are independently allocated.
pub const OutputData = struct {
    root: []const u8,
    depth: i32,
    stats: Stats,
    tree: []TreeEntry,
    symlinks_detected: ?[]SymlinkInfo = null, // Only when follow_symlinks: false and symlinks found
    errors: ?[]ErrorEntry = null, // Only when non-fatal errors occurred
    performance: ?PerformanceMetrics = null, // Only when performance: true
    _note: ?[]const u8 = null, // Only when force: true: "You asked for this"

    pub fn deinit(self: *OutputData, allocator: std.mem.Allocator) void {
        allocator.free(self.root);

        for (self.tree) |*entry| {
            entry.deinit(allocator);
        }
        allocator.free(self.tree);

        if (self.symlinks_detected) |symlinks| {
            for (symlinks) |*symlink| {
                symlink.deinit(allocator);
            }
            allocator.free(symlinks);
        }

        if (self.errors) |errors| {
            for (errors) |*err| {
                err.deinit(allocator);
            }
            allocator.free(errors);
        }

        if (self._note) |note| {
            allocator.free(note);
        }
    }
};

/// Fatal error that halts traversal (unless force mode is on).
///
/// Created by errors.buildLargeDirectoryError, errors.buildNonUtf8Error, or
/// errors.buildSymlinkCycleError. Serialized by output.serializeFatalError
/// into the JSON error response sent to stdout or MCP. All string fields are
/// independently allocated and must be freed via deinit.
pub const FatalError = struct {
    error_name: []const u8,
    type: ErrorType,
    path: []const u8,
    message: []const u8,

    /// Create a FatalError with all fields allocated
    /// Caller must call deinit() to free memory
    pub fn init(allocator: std.mem.Allocator, err_type: ErrorType, path: []const u8, message: []const u8) !FatalError {
        const error_name_literal = switch (err_type) {
            .large_directory => "Large directory detected",
            .non_utf8_filename => "Invalid filename encoding",
            .symlink_cycle => "Symlink cycle detected",
            else => "Fatal error",
        };

        // Allocate all fields for consistent ownership
        const error_name = try allocator.dupe(u8, error_name_literal);
        errdefer allocator.free(error_name);

        const path_copy = try allocator.dupe(u8, path);
        errdefer allocator.free(path_copy);

        // message is already allocated by the caller, but we need to own it
        // so we duplicate it for consistency
        const message_copy = try allocator.dupe(u8, message);

        return .{
            .error_name = error_name,
            .type = err_type,
            .path = path_copy,
            .message = message_copy,
        };
    }

    pub fn deinit(self: *FatalError, allocator: std.mem.Allocator) void {
        allocator.free(self.error_name);
        allocator.free(self.path);
        allocator.free(self.message);
    }
};

/// Success response returned when output is written to a file instead of stdout.
///
/// Created by output.serializeToFile after writing the JSON tree to disk.
/// Consumed by main.serializeFileSuccess to produce the final CLI/MCP response.
pub const FileOutputSuccess = struct {
    success: bool,
    message: []const u8,
    stats: Stats,

    pub fn deinit(self: *FileOutputSuccess, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
    }
};

/// Device-inode pair used for symlink cycle detection when follow_symlinks is true.
///
/// Computed by symlink.getDeviceInode from filesystem stat data. Stored in
/// TraversalState.visited_paths (AutoHashMap keyed by this type) to track
/// which real filesystem locations have already been traversed.
pub const VisitedPath = struct {
    dev: u64, // device ID
    ino: u64, // inode number

    pub fn eql(self: VisitedPath, other: VisitedPath) bool {
        return self.dev == other.dev and self.ino == other.ino;
    }

    pub fn hash(self: VisitedPath) u64 {
        // Simple hash combining device and inode
        return self.dev ^ self.ino;
    }
};

/// Mutable state container for an in-progress directory traversal.
///
/// Initialized by TraversalState.init at the start of tree.buildTree.
/// Passed by pointer through tree.traverseDirectory and tree.processEntry,
/// accumulating tree entries, symlink records, errors, stats, and performance
/// counters. After buildTree returns, main.buildOutputData borrows the
/// collected slices to assemble OutputData for serialization.
pub const TraversalState = struct {
    allocator: std.mem.Allocator,
    config: *const Config,
    stats: Stats,
    tree_entries: std.ArrayList(TreeEntry),
    symlinks: std.ArrayList(SymlinkInfo),
    errors: std.ArrayList(ErrorEntry),
    visited_paths: ?std.AutoHashMap(VisitedPath, void), // Only allocated when follow_symlinks: true
    current_byte_count: u64, // For token limit tracking in stdout mode
    performance: PerformanceMetrics,

    pub fn init(allocator: std.mem.Allocator, config: *const Config) !TraversalState {
        var state = TraversalState{
            .allocator = allocator,
            .config = config,
            .stats = Stats{},
            .tree_entries = std.ArrayList(TreeEntry){},
            .symlinks = std.ArrayList(SymlinkInfo){},
            .errors = std.ArrayList(ErrorEntry){},
            .visited_paths = null,
            .current_byte_count = 0,
            .performance = PerformanceMetrics{},
        };

        // Initialize visited_paths map if following symlinks
        if (config.follow_symlinks) {
            state.visited_paths = std.AutoHashMap(VisitedPath, void).init(allocator);
        }

        return state;
    }

    pub fn deinit(self: *TraversalState) void {
        for (self.tree_entries.items) |*entry| {
            entry.deinit(self.allocator);
        }
        self.tree_entries.deinit(self.allocator);

        for (self.symlinks.items) |*symlink| {
            symlink.deinit(self.allocator);
        }
        self.symlinks.deinit(self.allocator);

        for (self.errors.items) |*err| {
            err.deinit(self.allocator);
        }
        self.errors.deinit(self.allocator);

        if (self.visited_paths) |*visited| {
            visited.deinit();
        }
    }
};
