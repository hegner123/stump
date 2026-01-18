# Test Fixtures

This directory contains test fixtures for the stump MCP tool. Each subdirectory represents a different test scenario.

## Fixture Descriptions

### basic/
Simple directory structure with a few files and subdirectories.
- 1 hidden file (.hidden)
- 1 root file (file1.txt)
- 2 subdirectories with files

Use for: Basic functionality tests, simple traversal verification.

### deep/
Deeply nested directory structure (12+ levels).
- Single file at the deepest level

Use for: Testing depth limits, deep traversal, path handling.

### wide/
Single directory with many files (100 files).

Use for: Testing performance with many files in one directory, pagination.

### mixed/
Various file types and extensions.
- Text files (.txt)
- Shell scripts (.sh)
- JSON files (.json)
- Markdown files (.md)
- Image files (.png)
- Archive files (.tar.gz)
- Hidden files (.env)

Use for: Testing file extension filtering, type detection.

### symlinks/
Directory and file symbolic links.
- Regular files
- Symlink to file
- Symlink to directory
- Target directory with files

Use for: Testing symlink detection, symlink tracking in output.

### symlink-cycle/
Circular symbolic links between directories.
- dir1/link_to_dir2 -> ../dir2
- dir2/link_to_dir1 -> ../dir1

Use for: Testing cycle detection when follow_symlinks is enabled.

### utf8/
Various UTF-8 encoded filenames.
- Emoji (😀)
- Chinese (中文)
- Spanish (Ñoño)
- Hebrew (עברית)
- Japanese (日本語)
- Arabic (مرحبا)
- Russian (Привет)
- Chinese directory with file (目录/文件.txt)

Use for: Testing UTF-8 filename handling, internationalization.

### non-utf8/
Placeholder for non-UTF8 filename testing.
- Contains README with instructions
- On macOS, invalid UTF-8 filenames cannot be created
- Tests should mock filesystem layer or run on Linux

Use for: Testing fatal error handling for invalid UTF-8 filenames.

### large/
Large directory structure exceeding 10k token limit.
- 50 directories
- 20 files per directory
- 1000 files total

Use for: Testing token limit enforcement, large directory warning, file output mode.

## Usage in Tests

```zig
// Example test usage
const fixtures_path = "test/fixtures/";
const basic_path = fixtures_path ++ "basic";
const large_path = fixtures_path ++ "large";

// Test basic traversal
const result = try stump.traverse(basic_path, .{});

// Test token limit with large fixture
const large_result = try stump.traverse(large_path, .{ .token_limit = 10000 });
```

## Adding New Fixtures

When adding new fixtures:
1. Create a new subdirectory under test/fixtures/
2. Populate with test data
3. Document the fixture in this README
4. Update tests to use the new fixture
