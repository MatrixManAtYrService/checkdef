FROM nixos/nix:latest

# Install Python and basic tools
RUN nix-env -iA nixpkgs.python3 nixpkgs.git nixpkgs.bash nixpkgs.coreutils nixpkgs.gnused

# Enable experimental features
ENV NIX_CONFIG="experimental-features = nix-command flakes"

# Set working directory
WORKDIR /workspace

# Copy checkdef (current repo)
COPY checkdef /workspace/checkdef

# Copy checkdef-demo (from flake input)
COPY checkdef-demo /workspace/checkdef-demo

# Modify checkdef-demo to reference checkdef by path instead of URL
RUN cd /workspace/checkdef-demo && \
    sed -i 's|checkdef\.url = "[^"]*"|checkdef.url = "path:/workspace/checkdef"|' flake.nix

# Remove checkdef-demo input from checkdef (avoid circular dependency)
RUN cd /workspace/checkdef && \
    sed -i '/checkdef-demo\.url/d' flake.nix && \
    sed -i '/checkdef-demo\.flake/d' flake.nix

# Validate flake syntax after modifications
RUN cd /workspace/checkdef-demo && nix flake show .# --no-build
RUN cd /workspace/checkdef && nix flake show .# --no-build

# Default command
CMD ["/bin/bash"] 