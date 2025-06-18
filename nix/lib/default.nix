# Library re-exports - flattened structure for simpler usage
{ inputs, ... }:

# Return a function that takes pkgs and returns the lib modules
pkgs:
let
  # Import all individual check definitions (passing blueprint args where needed)
  checkModules = {
    deadnix = (import ./deadnix.nix) pkgs;
    statix = (import ./statix.nix) pkgs;
    nixpkgs-fmt = (import ./nixpkgs-fmt.nix) pkgs;
    ruff-check = (import ./ruff-check.nix) pkgs;
    ruff-format = (import ./ruff-format.nix) pkgs;
    pyright = (import ./pyright.nix) pkgs;
    fawltydeps = (import ./fawltydeps.nix) pkgs;
    pytest-cached = (import ./pytest-cached.nix { inherit inputs; }) pkgs;
    pdoc = (import ./pdoc.nix) pkgs;
    trim-whitespace = (import ./trim-whitespace.nix) pkgs;
  };

  # Extract check functions directly
  checkFunctions = builtins.mapAttrs (_: def: def.pattern) checkModules;

  # Import utils directly
  utils = (import ./utils.nix) pkgs;
in
{
  # Core framework functions and utilities
  inherit (utils) makeCheckWithDeps runner;
} // checkFunctions  # Merge in all check functions at the top level
