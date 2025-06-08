# fawltydeps check definition
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
    optionalArgs = [ "name" "description" "ignoreUndeclared" ];
    needsPythonEnv = true;
    makesChanges = false;
  };

  pattern = { src, pythonEnv, name ? "fawltydeps", description ? "Python dependency analysis with FawltyDeps", ignoreUndeclared ? [ ] }:
    let
      ignoreFlags =
        if ignoreUndeclared != [ ]
        then builtins.concatStringsSep " " (map (dep: "--ignore-undeclared ${dep}") ignoreUndeclared)
        else "";
    in
    makeCheckWithDeps {
      inherit name description src;
      dependencies = [ pythonEnv ];
      environment = { };
      script = ''
        echo "🔍 Running FawltyDeps dependency analysis..."
        
        # Run fawltydeps with ignore flags, but don't fail the build
        if fawltydeps ${ignoreFlags} 2>&1; then
          echo "✅ FawltyDeps analysis completed successfully"
        else
          echo "⚠️  FawltyDeps found dependency issues (see above)"
          echo "This is informational - continuing with build"
        fi
        
        echo "FawltyDeps check completed"
      '';
    };
}
