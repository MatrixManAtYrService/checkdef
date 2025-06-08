# Reusable check library functions
{ pkgs, ... }:

{
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

  # Nix linting check using deadnix + statix
  makeNixCheck = { deadnix ? true, statix ? true }: pkgs.stdenv.mkDerivation {
    name = "nix-linting";
    
    src = ./.;
    
    buildInputs = with pkgs; 
      (if deadnix then [ pkgs.deadnix ] else []) ++
      (if statix then [ pkgs.statix ] else []);
    
    buildPhase = ''
      set -euo pipefail
      
      echo "======================================"
      echo "🔍 Nix linting"
      echo "======================================"
      echo ""
      
      echo "Running comprehensive Nix linting..."
      
      # Find all .nix files in the project
      nix_files=$(find . -name "*.nix" -not -path "./.*" -not -path "./result*" | sort)
      
      if [ -z "$nix_files" ]; then
        echo "No .nix files found to check"
        exit 0
      fi
      
      echo "Checking $(echo "$nix_files" | wc -l) Nix files"
      exit_code=0
      
      ${if deadnix then ''
      # Tool 1: deadnix - Unused code detection
      echo ""
      echo "1️⃣ Checking for unused/dead code (deadnix)..."
      if deadnix $nix_files; then
        echo "✅ No unused code detected"
      else
        echo "❌ Found unused/dead code (see output above)"
        exit_code=1
      fi
      '' else ""}
      
      ${if statix then ''
      # Tool 2: statix - Comprehensive static analysis
      echo ""
      echo "2️⃣ Running comprehensive static analysis (statix)..."
      if statix check .; then
        echo "✅ Static analysis passed"
      else
        echo "❌ Static analysis found issues (see output above)"
        exit_code=1
      fi
      '' else ""}
      
      # Summary
      echo ""
      if [ $exit_code -eq 0 ]; then
        echo "🎉 All Nix files passed linting!"
        ${if deadnix then ''echo "   ✅ deadnix: No unused code"'' else ""}
        ${if statix then ''echo "   ✅ statix: No static analysis issues"'' else ""}
      else
        echo "❌ Some Nix files have linting issues"
        echo ""
        echo "Fix these issues:"
        ${if deadnix then ''echo "   - deadnix <files>      # unused code"'' else ""}
        ${if statix then ''echo "   - statix check <files> # comprehensive analysis"'' else ""}
        exit 1
      fi
    '';
    
    installPhase = ''
      mkdir -p $out
      echo "Nix linting - PASSED" > $out/result
    '';
  };

  # Python linting with ruff
  makePythonCheck = { check ? true, format ? true }: pkgs.stdenv.mkDerivation {
    name = "python-linting";
    
    src = ./.;
    
    buildInputs = with pkgs; [ ruff ];
    
    buildPhase = ''
      set -euo pipefail
      
      echo "======================================"
      echo "🔍 Python linting"
      echo "======================================"
      echo ""
      
      exit_code=0
      
      ${if check then ''
      echo "Running ruff check..."
      if ruff check .; then
        echo "✅ Ruff check passed"
      else
        echo "❌ Ruff check failed"
        exit_code=1
      fi
      echo ""
      '' else ""}
      
      ${if format then ''
      echo "Checking Python formatting..."
      if ruff format --check .; then
        echo "✅ Python formatting check passed"
      else
        echo "❌ Python formatting check failed"
        exit_code=1
      fi
      '' else ""}
      
      if [ $exit_code -ne 0 ]; then
        exit 1
      fi
    '';
    
    installPhase = ''
      mkdir -p $out
      echo "Python linting - PASSED" > $out/result
    '';
  };
}
