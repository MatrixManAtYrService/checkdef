# pytest-cached check definition - creates a derivation for caching
{ inputs, ... }:
pkgs:
let
  inherit (pkgs) lib;
  globset = inputs.globset.lib;
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
        extraEnvVars = { };
        pytestArgs = [ ];
      };

      finalTestConfig = lib.recursiveUpdate defaultTestConfig testConfig;

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
            runHook preBuild

            # Set up environment variables from testConfig
            ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg (toString v)}") finalTestConfig.extraEnvVars)}

            # Set wheel path if provided
            ${lib.optionalString (wheelPath != null) ''
              export ${wheelPathEnvVar}="${wheelPath}"
            ''}

            runHook postBuild
          '';

          checkPhase = ''
            runHook preCheck

            echo "🧪 Running pytest with flags: ${pytestFlags} ${builtins.concatStringsSep " " tests}"

            # Run the tests and capture results
            if pytest ${pytestFlags} ${builtins.concatStringsSep " " tests} ${builtins.concatStringsSep " " finalTestConfig.pytestArgs}; then
              test_result="PASSED"
              echo "✅ All tests passed!"
            else
              test_result="FAILED"
              echo "❌ Some tests failed"
              exit 1
            fi

            runHook postCheck
          '';

          installPhase = ''
            runHook preInstall

            mkdir -p $out

            # Create a summary file for the runner to read
            if [ "$test_result" = "PASSED" ]; then
              echo "PASSED" > $out/pytest_summary.txt
            else
              echo "FAILED" > $out/pytest_summary.txt
            fi

            # Store the command that was run for reference
            echo "pytest ${pytestFlags} ${builtins.concatStringsSep " " tests} ${builtins.concatStringsSep " " finalTestConfig.pytestArgs}" > $out/pytest_command.txt

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
      };
    };
}
