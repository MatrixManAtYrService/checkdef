# nixpkgs-fmt check definition

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

  pattern = { src, name ? "nixpkgs-fmt", description ? "Nix file formatting" }:
    makeCheckWithDeps {
      inherit name description src;
      dependencies = with pkgs; [ nixpkgs-fmt ];
      command = "find . -name \"*.nix\" -not -path \"./.*\" -not -path \"./result*\" -exec nixpkgs-fmt {} \\;";
    };
}
