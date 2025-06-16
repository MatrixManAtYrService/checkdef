# pdoc check definition
{ flake, inputs, ... }:

pkgs:
let
  inherit (pkgs) lib;

  # Import makeCheckWithDeps directly to avoid circular dependency
  utils = (import ./utils.nix { inherit flake inputs; }) pkgs;
  inherit (utils) makeCheckWithDeps;
in
{
  meta = {
    requiredArgs = [ "src" "pythonEnv" ];
    optionalArgs = [ "name" "description" "outputDir" "modulePath" ];
    needsPythonEnv = true;
    makesChanges = false;
  };

  pattern = { src, pythonEnv, name ? "pdoc", description ? "Generate API documentation with pdoc", outputDir ? "docs", modulePath ? "src/htutil" }:
    makeCheckWithDeps {
      inherit name description src;
      dependencies = with pkgs; [ pythonEnv ];
      command = "pdoc -o ${outputDir} ${modulePath}";
      environment = { };
      scriptTemplate = command: ''        
        # Create output directory if it doesn't exist
        mkdir -p ${outputDir}
        
        # Generate documentation
        ${command}
        
        echo "✅ Documentation generated successfully in ${outputDir}/"
      '';
    };
}
