{
  description = "Reusable development check definitions with Nix-based execution framework";

  inputs = {
    blueprint.url = "github:numtide/blueprint";
  };

  outputs = inputs: inputs.blueprint {
    inherit inputs;
    prefix = "nix";
  };
}
