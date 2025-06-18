# Pytest integration test check
pkgs:

let
  inherit (pkgs) lib;

  defaultEnvironment = {
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    PYTHONIOENCODING = "utf-8";
  };

  pattern = { src, pythonEnv ? pkgs.python3, checkdefDemoPath ? null, ... }:
    let
      utils = (import ./utils.nix) pkgs;

      checkdefDemoEnvPath = 
        if checkdefDemoPath != null 
        then checkdefDemoPath 
        else throw "checkdefDemoPath is required for pytest integration tests";

    in utils.makeCheckWithDeps {
      name = "pytest-integration";
      description = "Checkdef cache behavior integration tests";
      
      command = ''
        cd ${src}
        export CHECKDEF_DEMO_PATH="${checkdefDemoEnvPath}"
        ${pythonEnv}/bin/pytest tests/test_cache_behavior.py -v
      '';
      
      verboseCommand = ''
        cd ${src}
        export CHECKDEF_DEMO_PATH="${checkdefDemoEnvPath}"
        ${pythonEnv}/bin/pytest tests/test_cache_behavior.py -v -s --tb=long
      '';

      dependencies = [ pythonEnv pkgs.docker ];
      
      environment = defaultEnvironment // {
        CHECKDEF_DEMO_PATH = "${checkdefDemoEnvPath}";
      };
    };

in
{
  inherit pattern;
} 