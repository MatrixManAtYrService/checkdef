# Self-checks checklist for the checks framework
{ pkgs, pname ? "checklist", ... }:

let

  # Import check definitions directly to avoid circular dependency
  utils = (import ../lib/utils.nix) pkgs;
  inherit (utils) runner;

  # will be executed on this repo
  deadnixCheck = (import ../lib/deadnix.nix) pkgs;
  statixCheck = (import ../lib/statix.nix) pkgs;
  nixpkgsFmtCheck = (import ../lib/nixpkgs-fmt.nix) pkgs;
  trimWhitespaceCheck = (import ../lib/trim-whitespace.nix) pkgs;

  # script generation validation only
  pyrightCheck = (import ../lib/pyright.nix) pkgs;
  ruffCheckCheck = (import ../lib/ruff-check.nix) pkgs;
  ruffFormatCheck = (import ../lib/ruff-format.nix) pkgs;
  pdocCheck = (import ../lib/pdoc.nix) pkgs;
  fawltydepsCheck = (import ../lib/fawltydeps.nix) pkgs;

  # Dummy python environment for script generation validation
  dummyPythonEnv = pkgs.python3.withPackages (ps: [ ps.pip ]);

  # Project source
  src = ../../.;

  # Relevant checks that should actually be executed on this repo
  relevantChecks = {
    deadnix = deadnixCheck.pattern { inherit src; };
    statix = statixCheck.pattern { inherit src; };
    nixpkgs-fmt = nixpkgsFmtCheck.pattern { inherit src; };
    trim-whitespace = trimWhitespaceCheck.pattern {
      inherit src;
      filePatterns = [ "*.nix" "*.md" ];
    };
  };

  # Python/irrelevant checks - just for script generation validation (not execution)
  validationOnlyChecks = {
    pyright = pyrightCheck.pattern {
      inherit src;
      pythonEnv = dummyPythonEnv;
    };
    ruff-check = ruffCheckCheck.pattern { inherit src; };
    ruff-format = ruffFormatCheck.pattern { inherit src; };
    pdoc = pdocCheck.pattern {
      inherit src;
      pythonEnv = dummyPythonEnv;
      modulePath = "example/module";
    };
    fawltydeps = fawltydepsCheck.pattern {
      inherit src;
      pythonEnv = dummyPythonEnv;
      ignoreUndeclared = [ "example" ];
    };
  };

  # ALL checks for validation - both relevant and irrelevant
  allChecksForValidation = relevantChecks // validationOnlyChecks;

  # Build individual validation scripts for ALL checks
  individualValidationScripts = builtins.mapAttrs
    (checkName: checkDef:
      runner {
        name = "${pname}-${checkName}-validation";
        suiteName = "Checkdef ${checkName} Script Generation";
        scriptChecks = { "${checkName}" = checkDef; };
      }
    )
    allChecksForValidation;

  # Build the execution scripts for relevant checks
  relevantExecution = runner {
    name = "${pname}-execution";
    suiteName = "Checkdef Relevant Checks";
    scriptChecks = relevantChecks;
  };

in
# Create a wrapper script that validates generated scripts as one of the checks
pkgs.writeShellScriptBin pname ''
  set -euo pipefail

  # Create a temporary directory for validation files
  temp_dir=$(mktemp -d)
  trap 'rm -rf "$temp_dir"' EXIT

  echo "🚀 running checklist: Checkdef Self-Checks"

  # Script validation check
  echo "================================================"
  echo "[script-validation] Generated script validation (shellcheck)"
  echo "================================================"

  # Track overall validation status
  overall_validation_failed=false

  # Validate each check individually
  ${builtins.concatStringsSep "\n" (builtins.attrValues (builtins.mapAttrs (checkName: checkScript: ''

  echo "🔧 Validating ${checkName} script generation..."

  # Build the individual validation script for this check
  if ! nix build ${checkScript} --no-link 2>/tmp/${checkName}_build.log; then
    echo "❌ Failed to build ${checkName} validation script"
    cat /tmp/${checkName}_build.log
    echo "❌ ${checkName} script generation - FAILED"
    overall_validation_failed=true
    rm -f /tmp/${checkName}_build.log
  else
    rm -f /tmp/${checkName}_build.log

    # Validate the generated script
    script_path="${checkScript}/bin/${pname}-${checkName}-validation"
    check_failed=false

    # Check bash syntax
    if ! bash -n "$script_path" 2>/tmp/${checkName}_syntax.txt; then
      echo "❌ ${checkName}: Bash syntax validation failed:"
      cat /tmp/${checkName}_syntax.txt
      echo ""
      echo "💡 Generated script: $script_path"
      echo "Generated script content (with line numbers):"
      cat -n "$script_path"
      echo ""
      check_failed=true
      overall_validation_failed=true
    fi
    rm -f /tmp/${checkName}_syntax.txt

    # Check with shellcheck
    if ! ${pkgs.shellcheck}/bin/shellcheck "$script_path" 2>/tmp/${checkName}_shellcheck.txt; then
      echo "❌ ${checkName}: Shellcheck validation failed:"
      cat /tmp/${checkName}_shellcheck.txt
      echo ""
      echo "💡 Generated script: $script_path"
      echo "Generated script content (with line numbers):"
      cat -n "$script_path"
      echo ""
      check_failed=true
      overall_validation_failed=true
    fi
    rm -f /tmp/${checkName}_shellcheck.txt

    if [ "$check_failed" = "false" ]; then
      echo "✅ ${checkName} script validation - PASSED"
    else
      echo "❌ ${checkName} script validation - FAILED"
    fi
  fi
  '') individualValidationScripts))}

  # Show overall validation result
  if [ "$overall_validation_failed" = "true" ]; then
    echo "❌ Generated script validation - FAILED (see individual check failures above)"
  else
    echo "✅ Generated script validation - PASSED (all checks validated successfully)"
  fi

  echo ""

  # Run the actual relevant checks for this repository
  ${relevantExecution}/bin/${pname}-execution "$@"

  echo ""
  echo "🎉 All checks completed!"
''
