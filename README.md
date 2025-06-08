# Universal Development Checks Framework

A reusable Nix-based framework for running development checks with beautiful output and shell script execution. Designed to work seamlessly across different project types using pure Nix patterns and individual modular check definitions.

## ✨ Features

- 🎨 **Beautiful console output** with progress indicators and colored results
- 💾 **Intelligent caching** - leverages Nix's caching system for fast repeated runs
- 🔧 **Auto-fixing** - automatically applies fixes for formatting and linting issues
- 🔍 **Detailed error reporting** - shows full build output when checks fail
- 📊 **Comprehensive summaries** with execution statistics
- 🚀 **Extensible** - easy to add new check types as individual files
- 📋 **Pattern library** - pre-built patterns for common tools (deadnix, statix, ruff, pyright, etc.)
- 🏗️ **Blueprint structure** - follows modern Nix conventions with clean organization
- 🧩 **Modular design** - each check is defined in its own file for maintainability

## 🚀 Quick Start

### Adding to Your Project

Add this framework as a flake input in your `flake.nix`:

```nix
{
  description = "My awesome project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    checks.url = "github:yourusername/checks-framework";
    blueprint.url = "github:numtide/blueprint";
  };

  outputs = inputs: inputs.blueprint {
    inherit inputs;
  };
}
```

### Using the Framework

In your project's `nix/lib/checks.nix`:

```nix
# Check definitions and utilities
{ flake, inputs, ... }:

pkgs:
let
  inherit (pkgs.stdenv.hostPlatform) system;

  # Get the checks library
  checksLib = inputs.checks.lib pkgs;
  inherit (checksLib) patterns makeCheckScript;

  src = ../../.;

  fastChecks = {
    scriptChecks = {
      deadnix = patterns.deadnix { inherit src; };
      statix = patterns.statix { inherit src; };
      nixpkgs-fmt = patterns.nixpkgs-fmt { inherit src; };
      ruff-check = patterns.ruff-check { inherit src; };
      ruff-format = patterns.ruff-format { inherit src; };
    };
    derivationChecks = { };
  };

in
{
  inherit checksLib fastChecks;
}
```

Then create check packages in `nix/packages/`:

```nix
# nix/packages/checks-fast.nix
{ flake, pkgs, ... }:

let
  lib = flake.lib pkgs;
  inherit (lib.checks) checksLib fastChecks;
in
checksLib.makeCheckScript ({
  name = "my-project-checks-fast";
  suiteName = "Fast Checks";
} // fastChecks)
```

Run your checks:

```bash
nix run .#checks-fast
```

## 📋 Available Patterns

The framework includes patterns for common development tools:

### Nix Tools
- **deadnix** - Dead code detection
- **statix** - Static analysis 
- **nixpkgs-fmt** - Code formatting

### Python Tools  
- **ruff-check** - Fast Python linting
- **ruff-format** - Fast Python formatting
- **pyright** - Type checking (requires Python environment)
- **pytest-cached** - Cached test execution
- **fawltydeps** - Dependency analysis

### Universal Tools
- **uv-cli-test** - Test CLI tools across Python versions

## 🏗️ Project Structure

The framework follows [blueprint](https://numtide.github.io/blueprint/) conventions with individual check files:

```
├── flake.nix              # Main flake configuration (with nix/ prefix)
├── package.nix            # Default package (self-checks)
├── devshell.nix           # Development environment
└── nix/
    ├── lib/
    │   ├── default.nix     # Library re-exports (htutil pattern)
    │   ├── framework.nix   # Core makeCheckWithDeps function
    │   ├── patterns.nix    # Imports all individual checks
    │   ├── utils.nix       # makeCheckScript utility
    │   ├── deadnix.nix     # Individual check definitions
    │   ├── statix.nix      
    │   ├── nixpkgs-fmt.nix 
    │   ├── ruff-check.nix  
    │   ├── ruff-format.nix 
    │   ├── pyright.nix     
    │   ├── fawltydeps.nix  
    │   └── pytest-cached.nix
    └── packages/
        ├── default.nix     # Default package (self-checks)
        └── self-checks.nix # Self-checks package
```

## 🧪 Adding Custom Patterns

Create new patterns by adding a new file in `nix/lib/`:

```nix
# nix/lib/my-custom-check.nix
{ flake, inputs, ... }:

pkgs:
let
  inherit (pkgs) lib;
  
  # Import makeCheckWithDeps directly to avoid circular dependency
  framework = (import ./framework.nix { inherit flake inputs; }) pkgs;
  inherit (framework) makeCheckWithDeps;
in
{
  meta = {
    requiredArgs = [ "src" ];
    optionalArgs = [ "name" "description" ];
    needsPythonEnv = false;
    makesChanges = false;
  };
  
  pattern = { src, name ? "my-check", description ? "My custom check" }:
    makeCheckWithDeps {
      inherit name description src;
      dependencies = with pkgs; [ my-tool ];
      script = ''
        echo "🔍 Running my custom check..."
        my-tool --check .
      '';
    };
}
```

Then add it to `nix/lib/patterns.nix`:

```nix
checkModules = {
  # ... existing checks ...
  my-custom-check = (import ./my-custom-check.nix { inherit flake inputs; }) pkgs;
};
```

## 🔧 Framework Functions

### `makeCheckWithDeps`

Creates a check configuration with dependencies and environment setup:

```nix
makeCheckWithDeps {
  name = "my-check";
  description = "Description of what this check does";
  src = ./.;
  dependencies = [ pkgs.some-tool ];
  environment = { MY_VAR = "value"; };
  script = ''
    echo "Running check..."
    some-tool --verify
  '';
}
```

### `makeCheckScript`

Combines multiple checks into a single executable script:

```nix
makeCheckScript {
  name = "combined-checks";
  suiteName = "Development Checks";
  checks = {
    check1 = patterns.deadnix { inherit src; };
    check2 = patterns.statix { inherit src; };
  };
}
```

## 🎯 Examples

See the framework's own self-checks for a working example:
- Run: `nix run github:yourusername/checks-framework`
- Code: [`package.nix`](./package.nix)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Add your check as a new file in `nix/lib/your-check.nix`
4. Add it to the imports in `nix/lib/patterns.nix`
5. Run the self-checks: `nix run .`
6. Commit your changes: `git commit -m 'Add amazing feature'`
7. Push to the branch: `git push origin feature/amazing-feature`
8. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
