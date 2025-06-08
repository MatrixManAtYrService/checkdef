# nixpkgs-fmt check definition
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

  pattern = { src, name ? "nixpkgs-fmt", description ? "Nix file formatting" }:
    makeCheckWithDeps {
      inherit name description src;
      dependencies = with pkgs; [ nixpkgs-fmt ];
      makes_changes = true;
      script = ''
        echo "🔧 Formatting Nix files..."
        find . -name "*.nix" -not -path "./.*" -not -path "./result*" -exec nixpkgs-fmt {} \;
        echo "Nix files formatted!"
      '';
    };
}
