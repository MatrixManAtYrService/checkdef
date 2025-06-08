# ruff-format definition  
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

  pattern = { src, name ? "ruff-format", description ? "Python formatting with ruff" }:
    makeCheckWithDeps {
      inherit name description src;
      dependencies = with pkgs; [ ruff ];
      makes_changes = true;
      script = ''
        echo "🔧 Running ruff format..."
        ruff format
      '';
    };
}
