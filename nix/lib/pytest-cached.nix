# pytest-cached check definition - creates a derivation for caching
# Debug version to troubleshoot file staging
pkgs:
let
  inherit (pkgs) lib;
  globset = pkgs.globset.lib;
in
{
  meta = {
    requiredArgs = [ "src" "pythonEnv" ];
    optionalArgs = [ "name" "description" "testConfig" "includePatterns" "tests" "wheelPath" "wheelPathEnvVar" "extraDeps" ];
    needsPythonEnv = true;
    makesChanges = false;
    isDerivedCheck = true;
  };

  pattern =
    { src
    , pythonEnv
    , name ? "pytest-cached"
    , description ? "Cached Python tests"
    , testConfig ? { }
    , includePatterns ? [ "src/**" "tests/**" ]
    , tests ? [ "tests" ]
    , wheelPath ? null
    , wheelPathEnvVar ? "WHEEL_PATH"
    , extraDeps ? [ ]
    }:
    let
      defaultTestConfig = {
        baseDeps = [ ];
        baseEnv = { };
      };
      finalTestConfig = defaultTestConfig // testConfig;

      # Add wheel path to environment if provided
      wheelEnv =
        if wheelPath != null
        then { "${wheelPathEnvVar}" = wheelPath; }
        else { };

      # Use globset to filter source files based on glob patterns
      srcForCache = lib.fileset.toSource {
        root = src;
        fileset = globset.globs src includePatterns;
      };

      # Create the derivation with a function to handle different pytest flags
      mkPytestDerivation = verboseMode:
        let
          pytestFlags =
            if verboseMode
            then "-v -s --log-cli-level=DEBUG"
            else "-v --tb=short";
        in
        pkgs.stdenvNoCC.mkDerivation {
          pname = name;
          version = "1.0.0";
          src = srcForCache;

          nativeBuildInputs = [ pythonEnv ] ++ extraDeps ++ finalTestConfig.baseDeps;

          # Set up environment variables
          buildPhase = ''
            echo "🧪 Running pytest${if verboseMode then " (verbose mode)" else ""}..."
            
            # Set up any wheel environment variables
            ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: value: ''
              export ${name}="${value}"
              echo "Using ${name}: $${name}"
            '') (finalTestConfig.baseEnv // wheelEnv))}

            # Run pytest and capture output
            set +e  # Don't exit on pytest failure, we want to parse results
            pytest_output=$(pytest ${pytestFlags} ${builtins.concatStringsSep " " tests} 2>&1)
            pytest_exit_code=$?
            set -e
            
            echo "$pytest_output"
            
            # Parse results from pytest output
            echo "📊 Test Results:"
            
            # Extract the summary line (e.g., "21 passed in 9.67s" or "19 passed, 2 skipped in 25.44s")
            summary_line=$(echo "$pytest_output" | grep -E "^=+ .* (passed|failed|skipped|error)" | tail -1 || echo "")
            
            if [ -n "$summary_line" ]; then
              echo "   $summary_line"
              
              # Clean up the summary for external consumption (remove the === markers)
              clean_summary=$(echo "$summary_line" | sed 's/^=*[[:space:]]*//' | sed 's/[[:space:]]*=*$//')
              echo "$clean_summary" > pytest_summary.txt
              
              # Check if there were failures or errors
              if echo "$summary_line" | grep -q "failed\|error"; then
                echo "❌ Tests failed!"
                exit 1
              else
                echo "✅ All tests passed!"
              fi
            else
              echo "⚠️  Could not parse test results"
              echo "Could not parse test results" > pytest_summary.txt
              # Still exit with pytest's exit code
              exit $pytest_exit_code
            fi
          '';

          installPhase = ''
            mkdir -p $out
            echo "pytest completed successfully" > $out/pytest-result
            
            # Save the test summary for external reading
            if [ -f pytest_summary.txt ]; then
              cp pytest_summary.txt $out/
            fi
            
            # Also save the full pytest output for debugging
            if [ -n "$pytest_output" ]; then
              echo "$pytest_output" > $out/pytest-full-output.txt
            fi
          '';

          meta = with lib; {
            inherit description;
            platforms = platforms.unix;
            # Add command information for display purposes
            command = "pytest ${pytestFlags} ${builtins.concatStringsSep " " tests}";
          };

          passthru = {
            # Allow creating verbose version of this derivation
            verbose = mkPytestDerivation true;

            run = pkgs.writeShellScriptBin "${name}-direct-run-error" ''
              #!/bin/sh
              echo "❌ The check '${name}' cannot be run directly."
              echo "💡 To run this check, include it in a 'checks.runner' and execute the runner."
              echo "   For example: nix run .#my-checklist"
              exit 1
            '';
          };
        };
    in
    # Return the normal (non-verbose) derivation by default
    mkPytestDerivation false;
}
