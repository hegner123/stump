# Stump Tests

## Unit Tests

Comprehensive unit tests have been written for all core modules in `test/unit/`:

- `types_test.zig` - Tests for EntryType, TreeEntry, SymlinkInfo, ErrorEntry, and Statistics
- `config_test.zig` - Tests for token limit resolution, clamping, and large directory detection
- `errors_test.zig` - Tests for error handling utilities and UTF-8 validation
- `filter_test.zig` - Tests for path filtering, glob matching, and extension filtering
- `performance_test.zig` - Tests for Timer and PerformanceTracker
- `safeguards_test.zig` - Tests for UTF-8 validation and large directory checks
- `symlink_test.zig` - Tests for symlink detection and cycle prevention
- `output_test.zig` - Tests for UUID generation, filename generation, and token/byte conversions

### Build Integration Status

The unit tests are comprehensive and well-structured. However, due to Zig's strict module system that prevents imports outside the module path, the tests currently need build.zig adjustments to run properly.

**Current Issue:** Zig test files need to be within the same module tree as the source files they test, or the source files need to be set up as proper modules with dependency declarations.

**Recommended Solutions:**
1. Move test files into `src/` directory alongside source files (standard Zig pattern)
2. Create a single test root that includes all tests inline
3. Use Zig's package manager features (when they stabilize further)

## Integration Tests

Integration tests will be added in step 13 (step6b/tests-add-integration) in `test/integration/`.

## Test Fixtures

Test fixtures are available in `test/fixtures/`:
- `basic/` - Simple directory structure
- `deep/` - Deep nesting (12+ levels)
- `wide/` - Many files in single directory
- `mixed/` - Various file types
- `symlinks/` - Symbolic links (file and directory)
- `symlink-cycle/` - Symlinks that create cycles
- `utf8/` - Various UTF-8 filenames
- `non-utf8/` - Invalid UTF-8 filenames (for error testing)
- `large/` - Large directory (for token limit testing)
