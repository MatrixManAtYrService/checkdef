# ruff-check definition
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
    requiredArgs = [ "src" ];
    optionalArgs = [ "name" "description" ];
    needsPythonEnv = false;
    makesChanges = true;
  };

  pattern = { src, name ? "ruff-check", description ? "Python linting with ruff" }:
    makeCheckWithDeps {
      inherit name description src;
      dependencies = with pkgs; [ ruff ];
      command = "ruff check --fix";
      makes_changes = true;
      scriptTemplate = command: ''
        ${command}
        echo "All checks passed!"
      '';
    };
}
