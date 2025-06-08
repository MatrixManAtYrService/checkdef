# pyright check definition
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
    requiredArgs = [ "src" "pythonEnv" ];
    optionalArgs = [ "name" "description" ];
    needsPythonEnv = true;
    makesChanges = false;
  };

  pattern = { src, pythonEnv, name ? "pyright", description ? "Python type checking with pyright" }:
    makeCheckWithDeps {
      inherit name description src;
      dependencies = with pkgs; [ pyright pythonEnv ];
      environment = { };
      script = ''
        echo "🔍 Running pyright type checking..."
        pyright .
      '';
    };
}
