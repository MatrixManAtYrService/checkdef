# deadnix check definition
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

  pattern = { src, name ? "deadnix", description ? "Dead Nix code detection" }:
    makeCheckWithDeps {
      inherit name description src;
      dependencies = with pkgs; [ deadnix ];
      script = ''
        nix_files=$(find . -name "*.nix" -not -path "./.*" -not -path "./result*" | sort)
        if [ -z "$nix_files" ]; then
          echo "No .nix files found to check"
          exit 0
        fi
        echo "🔍 Running deadnix for unused code detection..."
        deadnix $nix_files
      '';
    };
}
