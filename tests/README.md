# Checkdef Tests

This directory contains integration tests for validating checkdef's cache behavior.

## Overview

The tests validate that checkdef's selective caching mechanism works correctly by:

1. **Performance Testing**: Measuring execution times across different cache states
2. **Selective Invalidation**: Ensuring changes to one module don't invalidate unrelated caches

## Running Tests

### Standard Checks (No Integration Tests)
```bash
nix run .#checklist
```

### With Integration Tests
```bash
nix run .#checklist -- --with-integration
```

### Direct Pytest Execution
```bash
nix develop
export CHECKDEF_DEMO_PATH="$(nix build .#inputs.checkdef-demo --no-link --print-out-paths)"
pytest tests/test_cache_behavior.py -v
```

## Requirements

- Container runtime (Docker or Podman)
- checkdef-demo flake input (automatically fetched)

## Test Structure

- `test_cache_behavior.py` - Main integration tests
- `docker/Dockerfile` - Container image for isolated testing
- `__init__.py` - Python package marker

## Environment Variables

- `CHECKDEF_DEMO_PATH` - Path to checkdef-demo source (automatically set by nix)
- `CONTAINER_TOOL` - Override container tool (docker/podman)

## Expected Behavior

The tests validate these timing relationships:
- `uncached_time > partially_cached_time > fully_cached_time`
- Changes to module A don't invalidate module B's cache 