# statix check definition

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
    makesChanges = false;
  };

  pattern = { src, name ? "statix", description ? "Nix static analysis" }:
    makeCheckWithDeps {
      inherit name description src;
      dependencies = with pkgs; [ statix ];
      command = "statix check .";
    };
}
