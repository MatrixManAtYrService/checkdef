{ pkgs, ... }:
pkgs.mkShell {
  buildInputs = with pkgs; [
    uv
    (python3.withPackages (ps: with ps; [ pytest ]))
    nixpkgs-fmt
    deadnix
    statix
    docker
    podman
  ];

  shellHook = ''
    echo "🔧 checkdef development environment"
    echo "Available tools: uv, pytest, docker/podman"
  '';
}
