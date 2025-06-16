{
  description = "Reusable development check definitions with Nix-based execution framework";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    blueprint.url = "github:numtide/blueprint";
  };

  outputs = inputs: inputs.blueprint {
    inherit inputs;
    prefix = "nix";
  };
}
