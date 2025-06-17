# Default package - simple placeholder to avoid circular dependency
{ pkgs, ... }:

# Create a simple script that explains how to use checkdef
pkgs.writeShellScriptBin "checkdef-info" ''
  echo "🔧 Checkdef - A Nix-based framework for development checks"
  echo ""
  echo "This is a library for creating development check frameworks."
  echo "To use checkdef in your project, add it as a flake input:"
  echo ""
  echo "  inputs.checkdef.url = \"github:your-org/checkdef\";"
  echo ""
  echo "Then use the checks in your flake.nix:"
  echo ""
  echo "  checks = checkdef.lib pkgs;"
  echo "  my-checklist = checks.runner { ... };"
  echo ""
  echo "See the README for complete examples."
''
