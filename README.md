# Universal development checks framework

A reusable framework for running development checks with beautiful output, caching awareness, and comprehensive error reporting.

## Features

- 🎨 **Beautiful Rich output** with progress indicators and colored results
- 💾 **Cache detection** - shows whether checks ran fresh or used cached results  
- 🔍 **Detailed error reporting** - shows full build output when checks fail
- 📊 **Comprehensive summaries** with execution statistics
- 🔧 **Extensible** - works with any Nix-based check system

## Usage

### As a Python script:
```bash
python check_runner.py "nixfmt:.#check-nixfmt" "tests:.#check-tests" --suite-name "My Project"
```

### As a Nix flake:
```nix
{
  inputs.checks.url = "path:/Users/matt/src/checks";
  
  outputs = { self, checks, ... }: {
    # Use the check runner in your project
    packages.default = checks.packages.${system}.runner;
  };
}
```

## Integration

This framework is designed to be imported into other projects. See the packages directory for pre-built integrations.
