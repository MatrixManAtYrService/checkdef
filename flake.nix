{
  description = "Reusable development check definitions with Nix-based execution framework";

  inputs = {
    blueprint.url = "github:numtide/blueprint";
    globset.url = "github:pdtpartners/globset";
    checkdef-demo.url = "github:MatrixManAtYrService/checkdef-demo";
    checkdef-demo.flake = false;
  };

  outputs = inputs: inputs.blueprint {
    inherit inputs;
    prefix = "nix";
  };
}
