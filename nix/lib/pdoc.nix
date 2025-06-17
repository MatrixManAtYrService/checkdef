# pdoc check definition

pkgs:
let
  # Import makeCheckWithDeps directly to avoid circular dependency
  utils = (import ./utils.nix) pkgs;
  inherit (utils) makeCheckWithDeps;
in
{
  meta = {
    requiredArgs = [ "src" "pythonEnv" ];
    optionalArgs = [ "name" "description" "outputDir" "modulePath" ];
    needsPythonEnv = true;
    makesChanges = true;
  };

  pattern = { pythonEnv, name ? "pdoc", description ? "Generate API documentation with pdoc", outputDir ? "docs", modulePath ? "src/htutil", src, ... }:
    makeCheckWithDeps {
      inherit name description src;
      dependencies = [ pythonEnv ];
      command = ''
        rm -rf ${outputDir}
        pdoc --html --output-dir . ${modulePath} 2>/dev/null || true
        if [ -d "${modulePath}" ]; then
          mv "${modulePath}" ${outputDir}
        fi
        echo "📚 Generated docs in ${outputDir}/ directory"
      '';
      verboseCommand = ''
        echo "🔧 Generating API documentation with pdoc..."
        rm -rf ${outputDir}
        pdoc --html --output-dir . ${modulePath}
        if [ -d "${modulePath}" ]; then
          mv "${modulePath}" ${outputDir}
        fi
        echo "📚 Generated docs in ${outputDir}/ directory"
      '';
    };
}
