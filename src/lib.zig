/// Library root that re-exports all modules for test access.
///
/// Referenced by build.zig as the root_source_file of the stump_lib_module.
/// Unit and integration tests import "stump" (this module) to reach internal
/// APIs without importing individual source files directly. Not used by the
/// main executable -- main.zig imports modules individually.
pub const types = @import("types.zig");
pub const config = @import("config.zig");
pub const tree = @import("tree.zig");
pub const output = @import("output.zig");
pub const errors = @import("errors.zig");
pub const performance = @import("performance.zig");
pub const filter = @import("filter.zig");
pub const safeguards = @import("safeguards.zig");
pub const symlink = @import("symlink.zig");
pub const mcp = @import("mcp.zig");
