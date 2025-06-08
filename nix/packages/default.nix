# Default package - runs the self-checks
{ flake, inputs, pkgs, ... }:

# Import the self-checks as the default package
import ./self-checks.nix { inherit flake inputs pkgs; }
