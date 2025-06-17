# ruff-format check definition

pkgs:
let
  # Import makeCheckWithDeps directly to avoid circular dependency
  utils = (import ./utils.nix) pkgs;
  inherit (utils) makeCheckWithDeps;
in
{
  meta = {
    requiredArgs = [ "src" ];
    optionalArgs = [ "name" "description" ];
    needsPythonEnv = false;
    makesChanges = true;
  };

  pattern = { name ? "ruff-format", description ? "Python formatting with ruff", src, ... }:
    makeCheckWithDeps {
      inherit name description src;
      dependencies = with pkgs; [ ruff ];
      command = "ruff format";
      verboseCommand = "ruff format --verbose";
    };
}
