# Self-checks package for the checks framework
{ flake, inputs, pkgs, pname ? "self-checks", ... }:

let
  inherit (pkgs) lib;

  # Get the framework functions and patterns from our lib  
  checksLib = flake.lib pkgs;
  inherit (checksLib) patterns makeCheckScript;

  # Project source
  src = ../../.;

  # Build individual checks using patterns
  scriptChecks = {
    deadnix = patterns.deadnix { inherit src; };
    statix = patterns.statix { inherit src; };
    nixpkgs-fmt = patterns.nixpkgs-fmt { inherit src; };
    ruff-check = patterns.ruff-check { inherit src; };
    ruff-format = patterns.ruff-format { inherit src; };
  };

in
# Use makeCheckScript to create the combined check script
makeCheckScript {
  name = pname;
  suiteName = "Self Checks";
  inherit scriptChecks;
}
