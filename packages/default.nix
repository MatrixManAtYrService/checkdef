# Standalone checks framework - bundle everything self-contained
{ pkgs, lib ? pkgs.lib, ... }:

let
  # Python environment with required dependencies
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    typer
    rich
  ]);
  
  # Bundle the Python runner script
  checkRunnerScript = pkgs.writeText "check_runner.py" (builtins.readFile ../check_runner.py);
  
  # Standard function to create a check derivation
  makeCheck = name: description: buildInputs: script: pkgs.stdenv.mkDerivation {
    inherit name;
    
    src = ./.;
    
    buildInputs = buildInputs ++ (with pkgs; [ coreutils ]);
    
    buildPhase = ''
      set -euo pipefail
      
      echo "======================================"
      echo "🔍 ${description}"
      echo "======================================"
      echo ""
      
      ${script}
    '';
    
    installPhase = ''
      mkdir -p $out
      echo "${description} - PASSED" > $out/result
    '';
  };
  
in
{
  # The universal check runner
  runner = pkgs.writeShellScriptBin "check-runner" ''
    set -euo pipefail
    
    # Use the bundled Python script
    ${pythonEnv}/bin/python ${checkRunnerScript} "$@"
  '';

  # Standard Nix linting check (deadnix + statix)
  nix-linting = makeCheck "nix-linting" "Nix linting (deadnix + statix)"
    (with pkgs; [ deadnix statix ]) ''
    echo "Running comprehensive Nix linting..."
    
    # Find all .nix files in the project
    nix_files=$(find . -name "*.nix" -not -path "./.*" -not -path "./result*" | sort)
    
    if [ -z "$nix_files" ]; then
      echo "No .nix files found to check"
      exit 0
    fi
    
    echo "Checking $(echo "$nix_files" | wc -l) Nix files"
    exit_code=0
    
    # Tool 1: deadnix - Unused code detection
    echo ""
    echo "1️⃣ Checking for unused/dead code (deadnix)..."
    if deadnix $nix_files; then
      echo "✅ No unused code detected"
    else
      echo "❌ Found unused/dead code (see output above)"
      exit_code=1
    fi
    
    # Tool 2: statix - Comprehensive static analysis
    echo ""
    echo "2️⃣ Running comprehensive static analysis (statix)..."
    if statix check .; then
      echo "✅ Static analysis passed"
    else
      echo "❌ Static analysis found issues (see output above)"
      exit_code=1
    fi
    
    # Summary
    echo ""
    if [ $exit_code -eq 0 ]; then
      echo "🎉 All Nix files passed linting!"
      echo "   ✅ deadnix: No unused code"
      echo "   ✅ statix: No static analysis issues"
    else
      echo "❌ Some Nix files have linting issues"
      echo ""
      echo "Fix these issues:"
      echo "   - deadnix <files>      # unused code"
      echo "   - statix check <files> # comprehensive analysis"
      exit 1
    fi
  '';
  
  # Nix formatting check
  nix-formatting = makeCheck "nix-formatting" "Nix file formatting" 
    (with pkgs; [ nixpkgs-fmt ]) ''
    echo "Checking Nix file formatting with nixpkgs-fmt..."
    
    # Find all .nix files
    nix_files=$(find . -name "*.nix" -not -path "./.*" -not -path "./result*")
    
    if [ -z "$nix_files" ]; then
      echo "No .nix files found to check"
      exit 0
    fi
    
    # Check if any files would be reformatted
    for file in $nix_files; do
      if ! nixpkgs-fmt --check "$file" >/dev/null 2>&1; then
        echo "❌ $file would be reformatted"
        echo "Run: nixpkgs-fmt $file"
        exit 1
      fi
    done
    
    echo "✅ All Nix files are properly formatted"
  '';

  # Python linting (ruff check + format)
  python-linting = makeCheck "python-linting" "Python linting (ruff check + format)"
    (with pkgs; [ ruff ]) ''
    echo "Running Python linting with ruff..."
    
    exit_code=0
    
    echo "Running ruff check..."
    if ruff check .; then
      echo "✅ Ruff check passed"
    else
      echo "❌ Ruff check failed"
      exit_code=1
    fi
    echo ""
    
    echo "Checking Python formatting..."
    if ruff format --check .; then
      echo "✅ Python formatting check passed"
    else
      echo "❌ Python formatting check failed"
      exit_code=1
    fi
    
    if [ $exit_code -ne 0 ]; then
      exit 1
    fi
  '';
  
  # Export utility functions
  inherit makeCheck;
}
