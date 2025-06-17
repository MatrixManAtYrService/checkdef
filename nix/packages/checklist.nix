# Self-checks checklist for the checks framework
{ flake, inputs, pkgs, pname ? "checklist", ... }:

let
  inherit (pkgs) lib;

  # Get the framework functions and check definitions from our lib  
  checks = flake.lib pkgs;
  inherit (checks) runner;

  # Project source
  src = ../../.;

  # Build individual checks using check definitions
  scriptChecks = {
    deadnix = checks.deadnix { inherit src; };
    statix = checks.statix { inherit src; };
    nixpkgs-fmt = checks.nixpkgs-fmt { inherit src; };
    ruff-check = checks.ruff-check { inherit src; };
    ruff-format = checks.ruff-format { inherit src; };
  };

in
# Use runner to create the combined check script
runner {
  name = pname;
  suiteName = "Self Checks";
  inherit scriptChecks;
}
