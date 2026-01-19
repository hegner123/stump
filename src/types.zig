const std = @import("std");

/// Tree entry type
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

/// Single tree entry in the output
pub const TreeEntry = struct {
    path: []const u8,
    type: EntryType,
    size: ?u64 = null, // Only for files, optional

    pub fn deinit(self: *TreeEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
    }
};

/// Symbolic link information (only when follow_symlinks: false)
pub const SymlinkInfo = struct {
    path: []const u8,
    target: []const u8,

    pub fn deinit(self: *SymlinkInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        allocator.free(self.target);
    }
};

/// Error type enumeration
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

/// Non-fatal error entry
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

/// Statistics about the traversal
pub const Stats = struct {
    dirs: u64 = 0,
    files: u64 = 0,
    filtered: u64 = 0,
    symlinks: u64 = 0,
    aborted_at: ?u64 = null, // Only set when token limit exceeded
    token_limit: ?u64 = null, // Only set when token limit exceeded
};

/// Performance metrics (optional, only when performance: true)
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

/// Sort options
pub const SortOption = enum {
    none,
    name,
    size,
    type_then_name,
};

/// Configuration for tree traversal
pub const Config = struct {
    // Input parameters
    dir: []const u8,
    depth: i32 = -1, // -1 means unlimited
    include_ext: ?[]const []const u8 = null,
    exclude_ext: ?[]const []const u8 = null,
    exclude_patterns: ?[]const []const u8 = null,
    show_hidden: bool = true,
    show_size: bool = true,
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

/// Complete JSON output structure
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

/// Fatal error response structure
/// All string fields are owned by this struct and must be freed
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

/// File output success response
pub const FileOutputSuccess = struct {
    success: bool,
    message: []const u8,
    stats: Stats,

    pub fn deinit(self: *FileOutputSuccess, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
    }
};

/// Visited path tracking for cycle detection (when follow_symlinks: true)
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

/// Traversal state
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
