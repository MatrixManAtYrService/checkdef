# pytest-cached check definition - creates a derivation for caching
{ flake, inputs, ... }:

pkgs:
let
  inherit (pkgs) lib;

  # Import makeCheckWithDeps directly to avoid circular dependency
  utils = (import ./utils.nix { inherit flake inputs; }) pkgs;
  inherit (utils) makeCheckWithDeps;
in
{
  meta = {
    requiredArgs = [ "src" "pythonEnv" ];
    optionalArgs = [ "name" "description" "testConfig" "includePaths" "testDirs" "wheelPath" "wheelPathEnvVar" "extraDeps" ];
    needsPythonEnv = true;
    makesChanges = false;
    isDerivedCheck = true;
  };

  pattern = { src, pythonEnv, name ? "pytest-cached", description ? "Cached Python tests", testConfig ? { }, includePaths ? [ "src" "tests" "pyproject.toml" ], testDirs ? [ "tests" ], wheelPath ? null, wheelPathEnvVar ? "WHEEL_PATH", extraDeps ? [ ] }:
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

      # Copy only the specified paths to nix store for deterministic caching
      srcForCache = lib.cleanSourceWith {
        inherit src;
        filter = path: _type:
          let
            relativePath = lib.removePrefix (toString src + "/") (toString path);
          in
          # Include only if the path starts with one of the specified include paths
          builtins.any
            (includePath:
              lib.hasPrefix (includePath + "/") relativePath || relativePath == includePath
            )
            includePaths;
      };
    in
    # Create a proper derivation that runs pytest
    pkgs.stdenvNoCC.mkDerivation {
      pname = "${name}";
      version = "1.0.0";
      src = srcForCache;

      nativeBuildInputs = [ pythonEnv ] ++ extraDeps ++ finalTestConfig.baseDeps;

      # Set up environment variables
      buildPhase = ''
        echo "🧪 Running pytest..."
        
        # Set up any wheel environment variables
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: value: ''
          export ${name}="${value}"
          echo "Using ${name}: $${name}"
        '') (finalTestConfig.baseEnv // wheelEnv))}
        
        # Run pytest and capture output
        set +e  # Don't exit on pytest failure, we want to parse results
        pytest_output=$(pytest -v --tb=short ${builtins.concatStringsSep " " testDirs} 2>&1)
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
      };
    };
}
