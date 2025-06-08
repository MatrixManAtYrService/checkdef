# Development shell for the checks framework
{ pkgs, ... }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    python3
    nixpkgs-fmt
    deadnix
    statix
    ruff
  ];

  shellHook = ''
    echo "🔧 Checks Framework Development Environment"
    echo "Available tools: python3, nixpkgs-fmt, deadnix, statix, ruff"
  '';
}
