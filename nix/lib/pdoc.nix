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
      environment = { };
      script = ''
        echo "📚 Generating API documentation with pdoc..."
        
        # Create output directory if it doesn't exist
        mkdir -p ${outputDir}
        
        # Generate documentation
        pdoc -o ${outputDir} ${modulePath}
        
        echo "✅ Documentation generated successfully in ${outputDir}/"
      '';
    };
}
