# checkdef

A Nix-based framework for running development checks with beautiful output and intelligent caching.

## Quick Start

Add checkdef to your `flake.nix` and define checks directly in your packages:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    checkdef.url = "path:/path/to/checkdef";
    # ... your other inputs
  };

  outputs = { self, nixpkgs, checkdef, ... }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    in {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          checks = checkdef.lib pkgs;
          src = ./.;
          # pythonEnv = ...; # your Python environment
        in {
          # Individual cached test suites
          checklist-unit = checks.pytest-cached {
            inherit src pythonEnv;
            name = "checklist-unit";
            includePatterns = [ "src/mymodule/**" "tests/unit/**" "pyproject.toml" ];
            testDirs = [ "tests/unit" ];
          };

          # Combined check script  
          checklist-all = checks.makeCheckScript {
            name = "checklist-all";
            suiteName = "All Checks";
            scriptChecks = {
              ruffCheck = checks.ruff-check { inherit src; };
              deadnixCheck = checks.deadnix { inherit src; };
            };
            derivationChecks = {
              unitTests = self.packages.${system}.checklist-unit;
            };
          };

          default = self.packages.${system}.checklist-all;
        });
    };
}
```

Run with:
```bash
nix run .#checklist-all     # Run all checks
nix run .#checklist-unit    # Run just unit tests
```

## scriptChecks vs derivationChecks

**scriptChecks** run directly in your shell:
- ❌ **Not cached** by Nix store - run every time
- ✅ **Can modify files** (auto-formatting, etc.)  
- ⚡ **Fast startup** - no build step

**derivationChecks** run in Nix build sandbox:
- ✅ **Cached by Nix** - only rebuild when inputs change
- ❌ **Cannot modify files** - read-only environment
- 🎯 **Precise invalidation** via `includePatterns`

## Input Scope Control

Control when checks rebuild by specifying `includePatterns` with glob patterns:

```nix
# Only rebuild when frontend code changes  
frontendTests = checks.pytest-cached {
  includePatterns = [ "frontend/**" "tests/frontend/**" "pyproject.toml" ];
  testDirs = [ "tests/frontend" ];
};

# Only rebuild when backend code changes
backendTests = checks.pytest-cached {
  includePatterns = [ "backend/**" "tests/backend/**" "pyproject.toml" ];
  testDirs = [ "tests/backend" ];
};
```

This enables **selective test execution** - frontend tests don't run when backend changes, and vice versa.

## Available Checks

- **deadnix** - Dead Nix code detection
- **statix** - Nix static analysis  
- **nixpkgs-fmt** - Nix formatting
- **trim-whitespace** - Remove trailing whitespace from files
- **ruff-check/ruff-format** - Python linting/formatting
- **pyright** - Python type checking
- **fawltydeps** - Python dependency analysis
- **pytest-cached** - Cached Python testing
- **pdoc** - Python documentation generation

## Writing Custom Checks

```nix
# Simple command-only check
myCheck = checks.makeCheckWithDeps {
  name = "my-tool";
  description = "Run my custom tool";
  command = "my-tool --check";
  dependencies = [ pkgs.my-tool ];
};

# Complex check with custom script
complexCheck = checks.makeCheckWithDeps {
  name = "complex";
  commandBuilder = "my-tool${if extraFlags != "" then " " + extraFlags else ""}";
  scriptTemplate = command: ''
    if ${command}; then
      echo "✅ Success"
    else
      echo "❌ Failed"
      exit 1
    fi
  '';
};
```

The framework ensures the displayed command matches what actually runs.

## Demo Project

See [checkdef-demo](https://github.com/example/checkdef-demo) for a complete working example showing selective test caching with a 40-second → 20-second improvement when only half the code changes.

