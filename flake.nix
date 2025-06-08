{
  description = "Reusable development checks framework with Python runner and Nix linting";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    blueprint.url = "github:numtide/blueprint";
  };

  outputs = inputs: inputs.blueprint {
    inherit inputs;
  };
}
