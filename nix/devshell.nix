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
    github-cli  # gh command for CI analysis
  ];

  shellHook = ''
    echo "🔧 checkdef development environment"
    echo "Available tools: uv, pytest, docker/podman, gh"
    echo "💡 For CI analysis, authenticate with: gh auth login"
  '';
}
