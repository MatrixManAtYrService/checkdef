# ruff-check check definition

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

  pattern = { name ? "ruff-check", description ? "Python linting with ruff", src, ... }:
    makeCheckWithDeps {
      inherit name description src;
      dependencies = with pkgs; [ ruff ];
      command = "ruff check --fix";
      verboseCommand = "ruff check --fix --verbose";
    };
}
