{
  description = "Reusable development check definitions with Nix-based execution framework";

  inputs = {
    blueprint.url = "github:numtide/blueprint";
    globset.url = "github:pdtpartners/globset";
    checkdef-demo = {
      url = "path:/Users/matt/src/checkdef-demo";
      flake = false;
    };
  };

  outputs = inputs: inputs.blueprint {
    inherit inputs;
    prefix = "nix";
  };
}
