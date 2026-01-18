# Non-UTF8 Filename Test Fixture

This fixture is designed to test handling of filenames with invalid UTF-8 sequences.

Note: Modern macOS enforces UTF-8 filenames and will not allow creation of
files with invalid UTF-8 sequences through standard filesystem APIs. 

For testing purposes:
- This directory can be manually populated with non-UTF8 filenames on Linux systems
- Alternatively, tests can mock the filesystem layer to simulate invalid UTF-8
- The stump tool should handle these gracefully when encountered

To create a test file on Linux:
```bash
# Create a file with invalid UTF-8 (byte sequence 0xFF is not valid UTF-8)
touch "$(printf 'test_\xff_invalid.txt')"
```

This directory contains only valid UTF-8 filenames as placeholders.
