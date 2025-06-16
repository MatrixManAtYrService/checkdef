# Library re-exports following htutil pattern
{ flake, inputs, ... }:

# Return a function that takes pkgs and returns the lib modules
pkgs: {
  # Core framework functions and utilities  
  inherit (import ./utils.nix { inherit flake inputs; } pkgs) makeCheckWithDeps makeCheckScript;

  # Check definitions (formerly patterns)
  inherit (import ./checkdef.nix { inherit flake inputs; } pkgs) checkdef;
}
