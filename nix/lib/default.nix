# Library re-exports - flattened structure for simpler usage
{ flake, inputs, ... }:

# Return a function that takes pkgs and returns the lib modules
pkgs:
let
  # Import all individual check definitions
  checkModules = {
    deadnix = (import ./deadnix.nix { inherit flake inputs; }) pkgs;
    statix = (import ./statix.nix { inherit flake inputs; }) pkgs;
    nixpkgs-fmt = (import ./nixpkgs-fmt.nix { inherit flake inputs; }) pkgs;
    ruff-check = (import ./ruff-check.nix { inherit flake inputs; }) pkgs;
    ruff-format = (import ./ruff-format.nix { inherit flake inputs; }) pkgs;
    pyright = (import ./pyright.nix { inherit flake inputs; }) pkgs;
    fawltydeps = (import ./fawltydeps.nix { inherit flake inputs; }) pkgs;
    pytest-cached = (import ./pytest-cached.nix { inherit flake inputs; }) pkgs;
    pdoc = (import ./pdoc.nix { inherit flake inputs; }) pkgs;
    trim-whitespace = (import ./trim-whitespace.nix { inherit flake inputs; }) pkgs;
  };

  # Extract check functions directly
  checkFunctions = builtins.mapAttrs (name: def: def.pattern) checkModules;
in
{
  # Core framework functions and utilities  
  inherit (import ./utils.nix { inherit flake inputs; } pkgs) makeCheckWithDeps runner;
} // checkFunctions  # Merge in all check functions at the top level
