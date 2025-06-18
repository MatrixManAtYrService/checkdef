# trim-whitespace check definition

pkgs:
let
  # Import makeCheckWithDeps directly to avoid circular dependency
  utils = (import ./utils.nix) pkgs;
  inherit (utils) makeCheckWithDeps;
in
{
  meta = {
    requiredArgs = [ "src" ];
    optionalArgs = [ "name" "description" "filePatterns" "exclude" ];
    needsPythonEnv = false;
    makesChanges = true;
  };

  pattern = { name ? "trim-whitespace", description ? "Remove trailing whitespace", filePatterns ? [ "*" ], exclude ? [ ".git" "node_modules" "result" ".direnv" ], src, ... }:
    let
      # Build pattern arguments for find command
      patternArgs = builtins.concatStringsSep " -o " (map (pat: "-name \"${pat}\"") filePatterns);
      excludeArgs = builtins.concatStringsSep " " (map (dir: "-not -path \"./${dir}*\"") exclude);
      findCommand = "find . \\( ${patternArgs} \\) -type f ${excludeArgs}";
    in
    makeCheckWithDeps {
      inherit name description src;
      dependencies = with pkgs; [ findutils gnused ];
      command = ''
        echo "Trimming trailing whitespace from files..."
        ${findCommand} -exec sed -i 's/[[:space:]]*$//' {} +
        echo "✅ Trailing whitespace trimmed"
      '';
      verboseCommand = ''
        echo "🔧 Finding files matching patterns: ${toString filePatterns}"
        echo "🔧 Excluding directories: ${toString exclude}"
        echo "🔧 Find command: ${findCommand}"

        ${findCommand} -exec sed -i 's/[[:space:]]*$//' {} +

        echo "✅ Trailing whitespace trimmed"
      '';
    };
}
