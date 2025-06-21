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
    optionalArgs = [ "name" "description" "ignoreUndeclared" "ignoreUnused" ];
    needsPythonEnv = true;
    makesChanges = false;
  };

  pattern = { src, pythonEnv, name ? "fawltydeps", description ? "Python dependency analysis with FawltyDeps", ignoreUndeclared ? [ ], ignoreUnused ? [ ] }:
    let
      # Automatically ignore fawltydeps itself since it's never imported by analyzed code
      allIgnoredUndeclared = ignoreUndeclared ++ [ "fawltydeps" ];
      allIgnoredUnused = ignoreUnused;

      ignoreUndeclaredFlags =
        if allIgnoredUndeclared != [ ]
        then builtins.concatStringsSep " " (map (dep: "--ignore-undeclared ${dep}") allIgnoredUndeclared)
        else "";

      ignoreUnusedFlags =
        if allIgnoredUnused != [ ]
        then builtins.concatStringsSep " " (map (dep: "--ignore-unused ${dep}") allIgnoredUnused)
        else "";

      allFlags = builtins.filter (flag: flag != "") [ ignoreUndeclaredFlags ignoreUnusedFlags ];
      ignoreFlags = builtins.concatStringsSep " " allFlags;

      baseCommand = "fawltydeps${if ignoreFlags != "" then " " + ignoreFlags else ""}";
      verboseCmd = "fawltydeps${if ignoreFlags != "" then " " + ignoreFlags else ""} -v";
    in
    makeCheckWithDeps {
      inherit name description src;
      dependencies = [ pythonEnv ];
      command = baseCommand;
      verboseCommand = verboseCmd;
      environment = { };
    };
}
