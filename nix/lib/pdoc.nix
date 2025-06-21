# pdoc check definition

pkgs:
let
  # Import makeCheckWithDeps directly to avoid circular dependency
  utils = (import ./utils.nix) pkgs;
  inherit (utils) makeCheckWithDeps;
in
{
  meta = {
    requiredArgs = [ "src" "pythonEnv" "modulePath" ];
    optionalArgs = [ "name" "description" "outputDir" ];
    needsPythonEnv = true;
    makesChanges = true;
  };

  pattern = { pythonEnv, name ? "pdoc", description ? "Generate API documentation with pdoc", outputDir ? "docs", modulePath, src, ... }:
    makeCheckWithDeps {
      inherit name description src;
      dependencies = [ pythonEnv ];
      command = ''
        rm -rf ${outputDir}
        pdoc --output-directory ${outputDir} ${modulePath}
        echo "📚 Generated docs in ${outputDir}/ directory"
      '';
    };
}
