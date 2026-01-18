const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard target and optimization options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main executable
    const exe = b.addExecutable(.{
        .name = "stump",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Install the executable
    b.installArtifact(exe);

    // Create run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    // Pass arguments to the run command
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Create run step
    const run_step = b.step("run", "Run the stump MCP server");
    run_step.dependOn(&run_cmd.step);

    // Create source module for testing
    const src_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Unit tests - use main.zig as the test root to get all the source files
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Integration tests
    const integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/integration/all_tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Add source modules as imports for integration tests
    integration_tests.root_module.addImport("stump", src_module);

    const run_integration_tests = b.addRunArtifact(integration_tests);

    // Test step that runs all tests
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_integration_tests.step);

    // Unit tests only
    const unit_test_step = b.step("test-unit", "Run unit tests only");
    unit_test_step.dependOn(&run_unit_tests.step);

    // Integration tests only
    const integration_test_step = b.step("test-integration", "Run integration tests only");
    integration_test_step.dependOn(&run_integration_tests.step);

    // Release builds with specific optimization levels
    const release_safe_exe = b.addExecutable(.{
        .name = "stump",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = .ReleaseSafe,
        }),
    });

    const release_fast_exe = b.addExecutable(.{
        .name = "stump",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });

    const release_small_exe = b.addExecutable(.{
        .name = "stump",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = .ReleaseSmall,
        }),
    });

    // Release build steps
    const install_safe = b.addInstallArtifact(release_safe_exe, .{});
    const install_fast = b.addInstallArtifact(release_fast_exe, .{});
    const install_small = b.addInstallArtifact(release_small_exe, .{});

    const release_safe_step = b.step("release-safe", "Build with ReleaseSafe optimization");
    release_safe_step.dependOn(&install_safe.step);

    const release_fast_step = b.step("release-fast", "Build with ReleaseFast optimization");
    release_fast_step.dependOn(&install_fast.step);

    const release_small_step = b.step("release-small", "Build with ReleaseSmall optimization");
    release_small_step.dependOn(&install_small.step);
}
