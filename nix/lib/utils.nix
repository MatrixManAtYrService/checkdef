# Core framework utilities - simplified based on actual usage
{ flake, inputs, ... }:

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

      # New command system - either static command or command-builder
      command = args.command or null;
      commandBuilder = args.commandBuilder or null;

      # Validate that exactly one of command or commandBuilder is provided
      commandCount = (if command != null then 1 else 0) + (if commandBuilder != null then 1 else 0);
      _commandCheck = if commandCount != 1 then throw "makeCheckWithDeps: exactly one of 'command' or 'commandBuilder' must be provided" else null;

      # Build the actual command string
      builtCommand = if command != null then command else commandBuilder;

      # Handle script vs script-template
      script = args.script or null;
      scriptTemplate = args.scriptTemplate or (command: command); # Default to identity function

      # Validate script arguments - now scriptTemplate always exists
      scriptCount = (if script != null then 1 else 0);
      _scriptCheck = if script != null && args ? scriptTemplate then throw "makeCheckWithDeps: cannot provide both 'script' and 'scriptTemplate'" else null;

      # Build the actual script
      builtScript = if script != null then script else (scriptTemplate builtCommand);

      # Extract optional arguments with defaults  
      dependencies = args.dependencies or [ ];
      environment = defaultEnvironment // (args.environment or { });

      # Resolve dependencies - always a simple list plus basic tools
      resolvedDeps = dependencies ++ (with pkgs; [ coreutils ]);
    in
    {
      inherit name description;
      command = builtCommand; # Pass through the built command for display
      # Create a script that sets up the environment and runs the check
      scriptContent = ''
        # Set up environment variables
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg (toString v)}") environment)}
        
        # Add dependencies to PATH
        export PATH="${lib.concatStringsSep ":" (map (dep: "${dep}/bin") resolvedDeps)}:$PATH"
        
        # Run the actual check script
        ${builtScript}
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
            ${if check.command != null then ''echo "🔧 Running: ${check.command}"'' else ""}
          
            # Execute the check script
            ${check.scriptContent}
          
            # If we get here, the check passed
            echo "✅ ${check.description} - PASSED"
          '')
          scriptChecks)
      );

      # Generate scripts for derivation-based checks
      # We need to build each derivation and read its results
      derivationBasedChecks = builtins.concatStringsSep "\n\n" (
        builtins.attrValues (builtins.mapAttrs
          (checkName: derivation:
            let
              # Extract description from derivation meta or use default
              description =
                if builtins.hasAttr "meta" derivation && builtins.hasAttr "description" derivation.meta
                then derivation.meta.description
                else "Cached check: ${checkName}";

              # Create a small script that builds the derivation
              buildScript = pkgs.writeShellScript "build-${checkName}" ''
                set -euo pipefail
              
                # Create a temporary directory for the build result link
                temp_dir=$(mktemp -d)
                result_link="$temp_dir/check-result"
              
                # Build the derivation
                if nix build ${derivation} --out-link "$result_link" 2>/dev/null; then
                  # Read the test summary from the build result if available
                  if [ -f "$result_link/pytest_summary.txt" ]; then
                    summary=$(cat "$result_link/pytest_summary.txt")
                    echo "✅ ${checkName} - $summary"
                  else
                    echo "✅ ${checkName} - PASSED"
                  fi
                else
                  echo "❌ ${checkName} - FAILED"
                  exit 1
                fi
              
                # Clean up temp directory
                rm -rf "$temp_dir"
              '';
            in
            ''
              echo "================================================"
              echo "[${checkName}] ${description}"
              echo "================================================"
              echo "🔧 Running: nix build ${derivation}"
              
              # Run the build script for ${checkName}
              ${buildScript}
            ''
          )
          derivationChecks)
      );

      # Combine all check scripts
      allCheckScripts = builtins.concatStringsSep "\n\n" (
        builtins.filter (s: s != "") [ scriptBasedChecks derivationBasedChecks ]
      );
    in
    pkgs.writeShellScriptBin name ''
      set -euo pipefail
      
      echo "🚀 Starting ${suiteName}"
      echo "================================================"
      
      ${allCheckScripts}
      
      echo "================================================"
      echo "🎉 All checks passed!"
    '';

in
{
  inherit makeCheckWithDeps runner;
}
