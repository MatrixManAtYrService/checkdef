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

  pattern = { name ? "trim-whitespace", description ? "Remove trailing whitespace", filePatterns ? [ "*.nix" "*.md" ], exclude ? [ ".git" "node_modules" "result" ".direnv" ], ... }:
    makeCheckWithDeps {
      inherit name description;
      dependencies = with pkgs; [ ripgrep gnused findutils ];
      command = ''
        echo "Checking for trailing whitespace in current directory..."

        # Build ripgrep glob patterns from filePatterns
        glob_args=""
        ${builtins.concatStringsSep "\n" (map (pattern: ''glob_args="$glob_args --glob '${pattern}'"'') filePatterns)}

        # Use ripgrep to find files with trailing whitespace, then use sed to fix them
        if files_with_whitespace=$(eval "rg --files-with-matches --no-ignore $glob_args '[[:space:]]$'" 2>/dev/null) && [ -n "$files_with_whitespace" ]; then
          echo "Found files with trailing whitespace, trimming..."
          printf '%s\n' "$files_with_whitespace" | xargs -P4 -I {} ${pkgs.gnused}/bin/sed -i 's/[[:space:]]*$//' {}
          echo "✅ Trailing whitespace trimmed"
        else
          echo "✅ No trailing whitespace found"
        fi
      '';
      verboseCommand = ''
        printf '%s\n' "🔧 Finding files matching patterns: ${toString filePatterns}"
        printf '%s\n' "🔧 Excluding directories: ${toString exclude}"
        printf '%s\n' "🔧 Working in current directory: $(pwd)"
        printf '%s\n' "🔧 Using ripgrep to find files with trailing whitespace..."

        # Build ripgrep glob patterns from filePatterns
        glob_args=""
        ${builtins.concatStringsSep "\n" (map (pattern: ''glob_args="$glob_args --glob '${pattern}'"'') filePatterns)}

        # Use ripgrep to find files with trailing whitespace, then use sed to fix them
        if files_with_whitespace=$(eval "rg --files-with-matches --no-ignore $glob_args '[[:space:]]$'" 2>/dev/null) && [ -n "$files_with_whitespace" ]; then
          printf '%s\n' "🔧 Found files with trailing whitespace, trimming..."
          printf '%s\n' "$files_with_whitespace" | xargs -P4 -I {} ${pkgs.gnused}/bin/sed -i 's/[[:space:]]*$//' {}
          echo "✅ Trailing whitespace trimmed"
        else
          echo "✅ No trailing whitespace found"
        fi
      '';
    };
}
