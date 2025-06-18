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
        echo "Checking for trailing whitespace..."

        # First, check if any files have trailing whitespace
        if ${findCommand} -exec grep -l '[[:space:]]$' {} \; | head -1 | grep -q .; then
          echo "Found files with trailing whitespace, trimming..."
          ${findCommand} -exec sed -i 's/[[:space:]]*$//' {} +
          echo "✅ Trailing whitespace trimmed"
        else
          echo "✅ No trailing whitespace found"
        fi
      '';
      verboseCommand = ''
        echo "🔧 Finding files matching patterns: ${toString filePatterns}"
        echo "🔧 Excluding directories: ${toString exclude}"
        echo "🔧 Find command: ${findCommand}"

        # First, check if any files have trailing whitespace
        if ${findCommand} -exec grep -l '[[:space:]]$' {} \; | head -1 | grep -q .; then
          echo "🔧 Found files with trailing whitespace, trimming..."
          ${findCommand} -exec sed -i 's/[[:space:]]*$//' {} +
          echo "✅ Trailing whitespace trimmed"
        else
          echo "✅ No trailing whitespace found"
        fi
      '';
    };
}
