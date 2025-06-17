# fawltydeps check definition

pkgs:
let
  # Import makeCheckWithDeps directly to avoid circular dependency
  utils = (import ./utils.nix) pkgs;
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

      baseCommand = "fawltydeps${if ignoreFlags != "" then " " + ignoreFlags else ""}";
      verboseCmd = "fawltydeps -v${if ignoreFlags != "" then " " + ignoreFlags else ""}";
    in
    makeCheckWithDeps {
      inherit name description src;
      dependencies = [ pythonEnv ];
      command = baseCommand;
      verboseCommand = verboseCmd;
      environment = { };
    };
}
