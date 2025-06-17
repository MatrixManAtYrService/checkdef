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
          echo "🔧 Running: ${verboseCommand}"
          ${verboseCommand}
        else
          ${command}
        fi
      '';
    };

  # Create complete check script derivation
  runner =
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
            echo "================================================"
            echo "[${checkName}] ${check.description}"
            echo "================================================"
          
            # Execute the check script
            ${check.scriptContent}
          
            # If we get here, the check passed
            echo "✅ ${check.description} - PASSED"
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
                echo "🔧 Nix build command: nix build \"$target_derivation\" --out-link \"$result_link\" (silent)"
                if nix build "$target_derivation" --out-link "$result_link" 2>/dev/null; then
                  build_success=true
                else
                  build_success=false
                fi
              fi
              
              if [ "$build_success" = "true" ]; then
                # Read the test summary from the build result if available
                if [ -f "$result_link/pytest_summary.txt" ]; then
                  summary=$(cat "$result_link/pytest_summary.txt")
                  echo "✅ ${checkName} - $summary"
                else
                  echo "✅ ${checkName} - PASSED"
                fi
              else
                echo "❌ ${checkName} - FAILED"
                # Clean up temp directory before exit
                rm -rf "$temp_dir"
                exit 1
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
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [ nix ];
      text = ''
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
        
        ${allCheckScripts}
        
        echo "================================================"
        echo "🎉 All checks passed!"
      '';
    };

in
{
  inherit makeCheckWithDeps runner;
}
