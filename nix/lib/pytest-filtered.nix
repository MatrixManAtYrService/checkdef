# pytest-filtered check definition - creates a derivation with automatic source filtering
_:
pkgs:
let
  inherit (pkgs) lib;
in
{
  meta = {
    requiredArgs = [ "src" "envBuilder" ];
    optionalArgs = [ "name" "description" "testConfig" "includePatterns" "tests" "wheelPath" "wheelPathEnvVar" "extraDeps" ];
    needsPythonEnv = false; # We build our own env
    makesChanges = false;
    isDerivedCheck = true;
    description = "Creates cached pytest derivations with automatic source filtering and environment building";

    # Documentation for the new interface
    envBuilder = {
      description = "Function that takes filtered source and returns a Python environment";
      example = "filteredSrc: uv2nix.lib.buildPythonEnv { src = filteredSrc; }";
      note = "This function is called once per unique filter pattern, enabling efficient caching";
    };
    includePatterns = {
      description = "Glob patterns for files to include in the test derivation for cache isolation";
      example = [ "src/mymodule/**" "tests/test_mymodule.py" "pyproject.toml" ];
      note = "Automatically includes common Python config files (pyproject.toml, uv.lock, etc.)";
    };
  };

  pattern =
    { src
    , envBuilder
    , name ? "pytest-filtered"
    , description ? "Filtered Python tests"
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
        extraEnvVars = { };
        pytestArgs = [ ];
      };

      finalTestConfig = lib.recursiveUpdate defaultTestConfig testConfig;

      # Merge baseEnv and extraEnvVars for all environment variables
      allEnvVars = finalTestConfig.baseEnv // finalTestConfig.extraEnvVars;

      # Separate PATH from other environment variables to handle it specially
      pathAdditions = allEnvVars.PATH or "";
      envVarsWithoutPath = builtins.removeAttrs allEnvVars [ "PATH" ];

      # Source filtering using simple glob pattern matching
      filterSource = patterns: src:
        let
          # Simple glob matching function
          matchesGlob = pattern: path:
            let
              # Convert glob pattern to a simple check
              # For now, use a simple approach that handles the most common cases
              checkPattern = pat: str:
                if pat == "**" then true  # ** matches everything
                else if lib.hasSuffix "/**" pat then
                # Pattern like "src/foo/**" - check if path starts with "src/foo/"
                  let prefix = lib.removeSuffix "/**" pat;
                  in lib.hasPrefix (prefix + "/") str || str == prefix
                else if lib.hasPrefix "**/" pat then
                # Pattern like "**/test_foo.py" - check if path ends with "/test_foo.py" or equals "test_foo.py"
                  let suffix = lib.removePrefix "**/" pat;
                  in lib.hasSuffix ("/" + suffix) str || str == suffix
                else if lib.hasInfix "*" pat then
                # Simple wildcard - for now just check if the non-wildcard parts match
                # This is a simplified implementation
                  let
                    parts = lib.splitString "*" pat;
                    checkParts = parts: str:
                      if parts == [ ] then str == ""
                      else if builtins.length parts == 1 then str == (builtins.head parts)
                      else
                        let
                          firstPart = builtins.head parts;
                          restParts = builtins.tail parts;
                        in
                        lib.hasPrefix firstPart str &&
                        checkParts restParts (lib.removePrefix firstPart str);
                  in
                  checkParts parts str
                else
                # Exact match
                  pat == str;
            in
            checkPattern pattern path;

          # Check if path matches any pattern
          matchesAnyPattern = path:
            let
              relPath = lib.removePrefix (toString src + "/") (toString path);
              allPatterns = patterns ++ [
                # Always include common Python config files
                "pyproject.toml"
                "setup.py"
                "setup.cfg"
                "uv.lock"
                "poetry.lock"
                "requirements.txt"
                # Include src/__init__.py for package recognition
                "src/__init__.py"
              ];
            in
            lib.any (pattern: matchesGlob pattern relPath) allPatterns;
        in
        lib.cleanSourceWith {
          inherit src;
          filter = path: type:
            # Always include directories for traversal
            type == "directory" ||
            # Include files matching patterns
            matchesAnyPattern path;
        };

      # Apply filtering to create cache-isolated source
      filteredSrc = filterSource includePatterns src;

      # Build Python environment using the provided builder function
      pythonEnv = envBuilder filteredSrc;

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
          src = filteredSrc;

          # Enable the check phase
          doCheck = true;

          nativeBuildInputs = [ pythonEnv ] ++ extraDeps ++ finalTestConfig.baseDeps;

          # Set up environment variables
          buildPhase = ''
            runHook preBuild

            # Set up environment variables from testConfig
            ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg (toString v)}") envVarsWithoutPath)}

            # Set wheel path if provided
            ${lib.optionalString (wheelPath != null) ''
              export ${wheelPathEnvVar}="${wheelPath}"
            ''}

            # Add PATH separately
            ${lib.optionalString (pathAdditions != "") ''
              export PATH="${pathAdditions}:$PATH"
            ''}

            runHook postBuild
          '';

          checkPhase = ''
            runHook preCheck

            echo "🧪 Running pytest with flags: ${pytestFlags} ${builtins.concatStringsSep " " tests}"

            # Set up a writable pytest cache directory to avoid permission errors
            export PYTEST_CACHE_DIR="$TMPDIR/.pytest_cache"
            mkdir -p "$PYTEST_CACHE_DIR"

            # Run the tests and capture both stdout and stderr
            mkdir -p $TMPDIR/pytest_logs

            if pytest ${pytestFlags} ${builtins.concatStringsSep " " tests} ${builtins.concatStringsSep " " finalTestConfig.pytestArgs} -o cache_dir="$PYTEST_CACHE_DIR" 2>&1 | tee $TMPDIR/pytest_logs/output.log; then
              echo "✅ All tests passed!"
              export PYTEST_RESULT="PASSED"
            else
              echo "❌ Some tests failed"
              export PYTEST_RESULT="FAILED"
              # Still capture the logs even on failure
              exit 1
            fi

            runHook postCheck
          '';

          installPhase = ''
            runHook preInstall

            mkdir -p $out

            # Create a summary file for the runner to read
            echo "''${PYTEST_RESULT:-FAILED}" > $out/pytest_summary.txt

            # Store the command that was run for reference
            echo "pytest ${pytestFlags} ${builtins.concatStringsSep " " tests} ${builtins.concatStringsSep " " finalTestConfig.pytestArgs}" > $out/pytest_command.txt

            # Store the captured logs for verbose mode display
            if [ -f "$TMPDIR/pytest_logs/output.log" ]; then
              cp "$TMPDIR/pytest_logs/output.log" "$out/build_logs.txt"
              echo "Stored pytest logs in build_logs.txt ($(wc -l < "$out/build_logs.txt") lines)"
            else
              echo "No pytest logs found to store"
              echo "No pytest logs captured" > "$out/build_logs.txt"
            fi

            runHook postInstall
          '';

          meta = {
            inherit description;
            command = "pytest ${pytestFlags} ${builtins.concatStringsSep " " tests}";
          };
        };

      # Create both normal and verbose versions
      normalDerivation = mkPytestDerivation false;
      verboseDerivation = mkPytestDerivation true;

    in
    # Return the normal derivation with verbose as a passthru
    normalDerivation // {
      passthru = {
        verbose = verboseDerivation;
        # Expose the filtered source and environment for debugging
        inherit filteredSrc pythonEnv;
      };
    };
}
