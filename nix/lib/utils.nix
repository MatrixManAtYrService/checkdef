# Core framework utilities - simplified based on actual usage
pkgs:
let
  inherit (pkgs) lib;

  defaultEnvironment = {
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    PYTHONIOENCODING = "utf-8";
  };

  makeCheckWithDeps = args:
    let
      # Extract required arguments
      name = args.name or (throw "makeCheckWithDeps: 'name' is required");
      description = args.description or name;
      command = args.command or (throw "makeCheckWithDeps: 'command' is required");

      # Extract optional arguments with defaults
      dependencies = args.dependencies or [ ];
      environment = defaultEnvironment // (args.environment or { });
      verboseCommand = args.verboseCommand or command;

      # Resolve dependencies - always a simple list plus basic tools
      resolvedDeps = dependencies ++ (with pkgs; [ coreutils ]);
    in
    {
      inherit name description command verboseCommand;
      # Create a script that sets up the environment and runs the check
      scriptContent = ''
        # Set up environment variables
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg (toString v)}") environment)}

        # Add dependencies to PATH
        export PATH="${lib.concatStringsSep ":" (map (dep: "${dep}/bin") resolvedDeps)}:$PATH"

        # Run the appropriate command based on verbose mode
        if [ "$verbose" = "true" ]; then
          ${verboseCommand}
        else
          ${command}
        fi
      '';
    };

  # Shared script generation logic
  generateScript =
    { name              # Script name (e.g., "htutil-checklist-fast")
    , suiteName ? name  # Name for the check suite (defaults to name)
    , scriptChecks ? { } # Script-based checks
    , derivationChecks ? { } # Derivation-based checks
    }:
    let
      # Generate scripts for traditional script-based checks
      scriptBasedChecks = builtins.concatStringsSep "\n\n" (
        builtins.attrValues (builtins.mapAttrs
          (checkName: check: ''
            # ============================================================================
            # CHECK: ${checkName} (from check definition file)
            # Description: ${check.description}
            # ============================================================================
            echo "================================================"
            echo "[${checkName}] ${check.description}"
            echo "================================================"

            # Start timing (using Python for precise timing)
            start_time=$(python3 -c "import time; print(f'{time.time():.3f}')")

            # Execute the check script
            ${check.scriptContent}

            # Calculate and display timing
            end_time=$(python3 -c "import time; print(f'{time.time():.3f}')")
            duration=$(python3 -c "print(f'{float(\"$end_time\") - float(\"$start_time\"):.3f}s')")

            # If we get here, the check passed
            echo "✅ ${check.description} - PASSED ($duration)"
          '')
          scriptChecks)
      );

      # Generate scripts for derivation-based checks
      derivationBasedChecks = builtins.concatStringsSep "\n\n" (
        builtins.attrValues (builtins.mapAttrs
          (checkName: derivation:
            let
              # Extract description from derivation meta or use default
              description =
                if builtins.hasAttr "meta" derivation && builtins.hasAttr "description" derivation.meta
                then derivation.meta.description
                else "Cached check: ${checkName}";

              # Get the verbose version if it exists
              verboseDerivation =
                if builtins.hasAttr "passthru" derivation && builtins.hasAttr "verbose" derivation.passthru
                then derivation.passthru.verbose
                else derivation;

              # Extract command information if available
              normalCommand =
                if builtins.hasAttr "meta" derivation && builtins.hasAttr "command" derivation.meta
                then derivation.meta.command
                else "";

              verboseCommand =
                if builtins.hasAttr "meta" verboseDerivation && builtins.hasAttr "command" verboseDerivation.meta
                then verboseDerivation.meta.command
                else "";
            in
            ''
              echo "================================================"
              echo "[${checkName}] ${description}"
              echo "================================================"

              # Start timing (using Python for precise timing)
              start_time=$(python3 -c "import time; print(f'{time.time():.3f}')")

              # Create a temporary directory for the build result link
              temp_dir=$(mktemp -d)
              result_link="$temp_dir/check-result"

              # Choose the appropriate derivation based on verbose mode
              if [ "$verbose" = "true" ]; then
                target_derivation="${verboseDerivation}"
                # Show the underlying command if available
                ${if verboseCommand != "" then ''echo "🔧 Underlying command: ${verboseCommand}"'' else ""}
                echo "🔧 Nix build command: nix build -v \"$target_derivation\" --out-link \"$result_link\" --print-build-logs"
                if nix build -v "$target_derivation" --out-link "$result_link" --print-build-logs; then
                  build_success=true
                else
                  build_success=false
                fi
              else
                target_derivation="${derivation}"
                # Show the underlying command if available
                ${if normalCommand != "" then ''echo "🔧 Underlying command: ${normalCommand}"'' else ""}
                echo "🔧 Nix build command: nix build \"$target_derivation\" --out-link \"$result_link\""
                if nix build "$target_derivation" --out-link "$result_link" 2>/dev/null; then
                  build_success=true
                else
                  build_success=false
                fi
              fi

              # Calculate timing
              end_time=$(python3 -c "import time; print(f'{time.time():.3f}')")
              duration=$(python3 -c "print(f'{float(\"$end_time\") - float(\"$start_time\"):.3f}s')")

              if [ "$build_success" = "true" ]; then
                # In verbose mode, show stored logs if available
                if [ "$verbose" = "true" ]; then
                  if [ -f "$result_link/build_logs.txt" ]; then
                    echo "🔧 Stored build logs:"
                    echo "----------------------------------------"
                    cat "$result_link/build_logs.txt"
                    echo "----------------------------------------"
                  elif [ -f "$result_link/pytest_output.txt" ]; then
                    echo "🔧 Stored pytest output:"
                    echo "----------------------------------------"
                    cat "$result_link/pytest_output.txt"
                    echo "----------------------------------------"
                  fi
                fi

                # Read the test summary from the build result if available
                if [ -f "$result_link/pytest_summary.txt" ]; then
                  summary=$(cat "$result_link/pytest_summary.txt")
                  echo "✅ ${checkName} - $summary ($duration)"
                else
                  echo "✅ ${checkName} - PASSED ($duration)"
                fi
              else
                echo "❌ ${checkName} - FAILED ($duration)"
                # Track failures but don't exit immediately
                if [ -z "''${FAILED_CHECKS:-}" ]; then
                  FAILED_CHECKS="${checkName}"
                else
                  FAILED_CHECKS="$FAILED_CHECKS,${checkName}"
                fi
              fi

              # Clean up temp directory
              rm -rf "$temp_dir"
            ''
          )
          derivationChecks)
      );

      # Combine all check scripts
      allCheckScripts = builtins.concatStringsSep "\n\n" (
        builtins.filter (s: s != "") [ scriptBasedChecks derivationBasedChecks ]
      );
    in
    ''
      set -euo pipefail

      verbose=false
      while getopts "v" opt; do
        case ''${opt} in
          v ) verbose=true;;
          \? ) echo "Usage: $0 [-v]"
               exit 1;;
        esac
      done

      export verbose
      echo "🚀 running checklist: ${suiteName}"

      # Initialize failed checks tracker
      FAILED_CHECKS=""

      ${allCheckScripts}

      echo "================================================"
      if [ -z "$FAILED_CHECKS" ]; then
        echo "🎉 All checks passed!"
      else
        echo "❌ Some checks failed: $FAILED_CHECKS"
        exit 1
      fi
    '';

  # Consumer-facing runner (no shellcheck validation)
  runner = args:
    let
      scriptText = generateScript args;
    in
    pkgs.writeShellScriptBin args.name scriptText;

  # Internal validator (with shellcheck validation)
  validator = args:
    let
      scriptText = generateScript args;
    in
    pkgs.runCommandLocal "${args.name}-validated"
      {
        buildInputs = with pkgs; [ shellcheck bash ];
      } ''
      echo "🔧 Validating generated script with shellcheck..."

      # First, write the script text to a temporary file and validate it
      echo "Step 0: Pre-validating script generation..."
      cat > temp_script.sh << 'SCRIPT_EOF'
      ${scriptText}
      SCRIPT_EOF

      # Check for basic bash syntax errors in the generated script
      if bash -n temp_script.sh 2>syntax_errors.txt; then
        echo "✅ Script generation syntax validation passed"
      else
        echo "❌ Script generation failed - syntax errors found!"
        echo ""
        echo "Syntax errors found:"
        cat syntax_errors.txt
        echo ""
        echo "💡 Hint: Check your check definition files for unmatched quotes or other syntax issues."
        echo "💡 Look for the CHECK comments in the generated script below to identify the problematic check."
        echo ""
        echo "==================== Generated Script (for debugging) ===================="
        cat -n temp_script.sh
        echo "========================================================================"
        exit 1
      fi

      # If syntax is valid, create the actual script
      script_path="${args.name}"
      cat > "$script_path" << 'SCRIPT_EOF'
      #!/bin/bash
      ${scriptText}
      SCRIPT_EOF
      chmod +x "$script_path"

      echo "Script created successfully: $script_path"

      # Then run shellcheck for style/best practices
      echo "Step 1: Running shellcheck for style validation..."
      echo "Running: shellcheck $script_path"
      if shellcheck -f tty "$script_path"; then
        echo "✅ Shellcheck validation passed - no issues found"
      else
        echo "❌ Shellcheck validation failed"
        echo ""
        echo "💡 Hint: Look for the CHECK comments in the generated script below to identify the problematic check."
        echo ""
        echo "==================== Generated Script (for debugging) ===================="
        cat -n "$script_path"
        echo "========================================================================"
        exit 1
      fi

      # Copy the validated script to output
      mkdir -p $out/bin
      cp "$script_path" "$out/bin/${args.name}"
      chmod +x "$out/bin/${args.name}"

      echo "✅ Script validation completed successfully"
    '';

in
{
  inherit makeCheckWithDeps generateScript runner validator;
}
