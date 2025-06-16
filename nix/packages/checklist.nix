# Self-checks checklist for the checks framework
{ flake, inputs, pkgs, pname ? "checklist", ... }:

let
  inherit (pkgs) lib;

  # Get the framework functions and check definitions from our lib  
  checksLib = flake.lib pkgs;
  inherit (checksLib) checkdef makeCheckScript;

  # Project source
  src = ../../.;

  # Build individual checks using check definitions
  scriptChecks = {
    deadnix = checkdef.deadnix { inherit src; };
    statix = checkdef.statix { inherit src; };
    nixpkgs-fmt = checkdef.nixpkgs-fmt { inherit src; };
    ruff-check = checkdef.ruff-check { inherit src; };
    ruff-format = checkdef.ruff-format { inherit src; };
  };

in
# Use makeCheckScript to create the combined check script
makeCheckScript {
  name = pname;
  suiteName = "Self Checks";
  inherit scriptChecks;
}
