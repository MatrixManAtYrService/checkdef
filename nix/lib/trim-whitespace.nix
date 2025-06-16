# trim-whitespace check definition
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
    requiredArgs = [ "src" ];
    optionalArgs = [ "name" "description" "filePattern" "exclude" ];
    needsPythonEnv = false;
    makesChanges = true;
  };

  pattern = { src, name ? "trim-whitespace", description ? "Remove trailing whitespace", filePatterns ? [ "*" ], exclude ? [ ".git" "node_modules" "result" ".direnv" ] }:
    let
      excludeArgs = lib.concatStringsSep " " (map (dir: "-not -path './${dir}/*'") exclude);
      # Generate find conditions for multiple patterns
      patternArgs = lib.concatStringsSep " -o " (map (pattern: "-name '${pattern}'") filePatterns);
      findCommand = "find . \\( ${patternArgs} \\) -type f ${excludeArgs}";
    in
    makeCheckWithDeps {
      inherit name description src;
      dependencies = with pkgs; [ findutils gnused ];
      command = "${findCommand} -exec sed -i 's/[[:space:]]*$//' {} +";
      makes_changes = true;
      scriptTemplate = command: ''
        # Find files and remove trailing whitespace
        files_found=$(${findCommand} | wc -l)
        if [ "$files_found" -eq 0 ]; then
          echo "No files found matching patterns: ${lib.concatStringsSep ", " filePatterns}"
          exit 0
        fi
        
        echo "Processing $files_found files..."
        ${command}
        echo "Trailing whitespace removed from all matching files"
      '';
    };
}
