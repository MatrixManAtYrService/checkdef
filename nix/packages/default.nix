# Default package - runs the checklist
{ flake, inputs, pkgs, ... }:

# Import the checklist as the default package
import ./checklist.nix { inherit flake inputs pkgs; }
