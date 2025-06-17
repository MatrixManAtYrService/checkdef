# Self-checks checklist for the checks framework
{ inputs, pkgs, pname ? "checklist", ... }:

let
  # Use nixpkgs input to get a separate pkgs instance
  inherit (inputs) nixpkgs;
  selfCheckPkgs = nixpkgs.legacyPackages.${pkgs.system};

  # Import check definitions directly to avoid circular dependency
  utils = (import ../lib/utils.nix) selfCheckPkgs;
  deadnixCheck = (import ../lib/deadnix.nix) selfCheckPkgs;
  statixCheck = (import ../lib/statix.nix) selfCheckPkgs;
  nixpkgsFmtCheck = (import ../lib/nixpkgs-fmt.nix) selfCheckPkgs;

  inherit (utils) runner;

  # Project source
  src = ../../.;

  # Build individual checks using check definitions
  # Only include Nix-related checks since this is a Nix-only project
  scriptChecks = {
    deadnix = deadnixCheck.pattern { inherit src; };
    statix = statixCheck.pattern { inherit src; };
    nixpkgs-fmt = nixpkgsFmtCheck.pattern { inherit src; };
  };

in
# Use runner to create the combined check script
runner {
  name = pname;
  suiteName = "Checkdef Self-Checks";
  inherit scriptChecks;
}
