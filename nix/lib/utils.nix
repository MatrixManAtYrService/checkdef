# Core framework utilities - both makeCheckWithDeps and makeCheckScript
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
      # Extract arguments with defaults
      name = args.name or (throw "makeCheckWithDeps: 'name' is required");
      description = args.description or name;
      script = args.script or (throw "makeCheckWithDeps: 'script' is required");
      makes_changes = args.makes_changes or false;

      # Dependencies can be specified multiple ways:
      # 1. buildInputs (legacy, direct list)
      # 2. dependencies (new, can be list or attrset)
      # 3. projectDeps (attrset of named dependencies)
      buildInputs = args.buildInputs or [ ];
      dependencies = args.dependencies or [ ];
      projectDeps = args.projectDeps or { };

      # Environment variables (without IN_NIX_BUILD since we're running directly)
      environment = defaultEnvironment // (args.environment or { });

      # Resolve dependencies
      resolvedDeps =
        # Legacy buildInputs
        buildInputs ++
        # Direct dependencies list
        (if lib.isList dependencies then dependencies else lib.attrValues dependencies) ++
        # Project dependencies
        (lib.attrValues projectDeps) ++
        # Always include basic tools
        (with pkgs; [ coreutils ]);

      # Handle named dependency substitution in script
      # Replace @depName@ with actual paths in the script
      processedScript = lib.foldl'
        (script: depName:
          let depPkg = projectDeps.${depName}; in
          builtins.replaceStrings [ "@${depName}@" ] [ "${depPkg}" ] script
        )
        script
        (lib.attrNames projectDeps);

    in
    {
      inherit name description makes_changes;
      # Create a script that sets up the environment and runs the check
      scriptContent = ''
        echo "🔧 Running ${name}..."
        
        # Set up environment variables
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg (toString v)}") environment)}
        
        # Add dependencies to PATH
        export PATH="${lib.concatStringsSep ":" (map (dep: "${dep}/bin") resolvedDeps)}:$PATH"
        
        # Run the actual check script
        ${processedScript}
      '';
    };

  # Create complete check script derivation
  makeCheckScript =
    { name              # Script name (e.g., "htutil-checks-fast")
    , suiteName         # Name for the check suite
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
              
                echo "================================================"
                echo "[${checkName}] ${description}"
                echo "================================================"
              
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
  inherit makeCheckWithDeps makeCheckScript;
}
