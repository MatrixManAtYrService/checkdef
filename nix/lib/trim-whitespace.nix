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
    makeCheckWithDeps {
      inherit name description src;
      dependencies = with pkgs; [ ripgrep gnused findutils ];
      command = ''
        echo "Checking for trailing whitespace..."

        # Use ripgrep to find files with trailing whitespace, then use sed to fix them
        if files_with_whitespace=$(rg --files-with-matches --no-ignore --glob "*.nix" --glob "*.md" "[[:space:]]$" 2>/dev/null) && [ -n "$files_with_whitespace" ]; then
          echo "Found files with trailing whitespace, trimming..."
          printf '%s\n' "$files_with_whitespace" | xargs -P4 -I {} sed -i 's/[[:space:]]*$//' {}
          echo "✅ Trailing whitespace trimmed"
        else
          echo "✅ No trailing whitespace found"
        fi
      '';
      verboseCommand = ''
        printf '%s\n' "🔧 Finding files matching patterns: ${toString filePatterns}"
        printf '%s\n' "🔧 Excluding directories: ${toString exclude}"
        printf '%s\n' "🔧 Using ripgrep to find files with trailing whitespace..."

        # Use ripgrep to find files with trailing whitespace, then use sed to fix them
        if files_with_whitespace=$(rg --files-with-matches --no-ignore --glob "*.nix" --glob "*.md" "[[:space:]]$" 2>/dev/null) && [ -n "$files_with_whitespace" ]; then
          printf '%s\n' "🔧 Found files with trailing whitespace, trimming..."
          printf '%s\n' "$files_with_whitespace" | xargs -P4 -I {} sed -i 's/[[:space:]]*$//' {}
          echo "✅ Trailing whitespace trimmed"
        else
          echo "✅ No trailing whitespace found"
        fi
      '';
    };
}
