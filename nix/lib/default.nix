# Library re-exports following htutil pattern
{ flake, inputs, ... }:

# Return a function that takes pkgs and returns the lib modules
pkgs: {
  # Core framework functions and utilities  
  inherit (import ./utils.nix { inherit flake inputs; } pkgs) makeCheckWithDeps makeCheckScript;

  # Check patterns
  inherit (import ./patterns.nix { inherit flake inputs; } pkgs) patterns;
}
