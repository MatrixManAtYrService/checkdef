# Check definitions - imports all individual check definitions
{ inputs, ... }:

pkgs:
let
  # Import all individual check definitions
  checkModules = {
    deadnix = (import ./deadnix.nix) pkgs;
    statix = (import ./statix.nix) pkgs;
    nixpkgs-fmt = (import ./nixpkgs-fmt.nix) pkgs;
    ruff-check = (import ./ruff-check.nix) pkgs;
    ruff-format = (import ./ruff-format.nix) pkgs;
    pyright = (import ./pyright.nix) pkgs;
    fawltydeps = (import ./fawltydeps.nix) pkgs;
    pdoc = (import ./pdoc.nix) pkgs;
  };

  # Extract check definitions
  checkdef = builtins.mapAttrs (_: def: def.pattern) checkModules;

in
{
  inherit checkdef;
}
