# pyright check definition

pkgs:
let
  # Import makeCheckWithDeps directly to avoid circular dependency
  utils = (import ./utils.nix) pkgs;
  inherit (utils) makeCheckWithDeps;
in
{
  meta = {
    requiredArgs = [ "src" "pythonEnv" ];
    optionalArgs = [ "name" "description" ];
    needsPythonEnv = true;
    makesChanges = false;
  };

  pattern = { pythonEnv, name ? "pyright", description ? "Python type checking with pyright", ... }:
    makeCheckWithDeps {
      inherit name description;
      dependencies = [ pythonEnv ];
      command = "pyright";
      verboseCommand = "pyright";
    };
}
