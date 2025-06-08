# statix check definition
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
    makesChanges = false;
  };

  pattern = { src, name ? "statix", description ? "Nix static analysis" }:
    makeCheckWithDeps {
      inherit name description src;
      dependencies = with pkgs; [ statix ];
      script = ''
        echo "🔍 Running statix for comprehensive static analysis..."
        statix check .
      '';
    };
}
