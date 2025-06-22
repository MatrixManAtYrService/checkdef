# CI analysis check - runs checkdef-demo CI twice and compares cache behavior
pkgs:

let

  defaultEnvironment = {
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    PYTHONIOENCODING = "utf-8";
  };

  pattern = { src, checkdefDemoPath ? null, ... }:
    let
      utils = (import ./utils.nix) pkgs;

      checkdefDemoEnvPath =
        if checkdefDemoPath != null
        then checkdefDemoPath
        else throw "checkdefDemoPath is required for CI analysis";

    in
    utils.makeCheckWithDeps {
      name = "ci-analysis";
      description = "CI cache behavior analysis - runs checkdef-demo CI twice and compares logs";

      command = ''
        set -euo pipefail
        
        echo "🧪 Starting CI cache behavior analysis..."
        echo "Using checkdef-demo from: ${checkdefDemoEnvPath}"
        
        # Instead of cd into nix store, use the repo URL directly
        REPO_URL="MatrixManAtYrService/checkdef-demo"
        
        # Check if we have the gh CLI available
        if ! command -v gh &> /dev/null; then
          echo "❌ GitHub CLI (gh) is required for CI analysis"
          echo "Please install it: https://cli.github.com/"
          exit 1
        fi
        
        # Check if we're authenticated with GitHub
        if ! gh auth status &> /dev/null; then
          echo "❌ Not authenticated with GitHub"
          echo "Please run: gh auth login"
          exit 1
        fi
        
        # Create temporary directory for logs
        log_dir=$(mktemp -d)
        trap 'rm -rf "$log_dir"' EXIT
        
        echo "📋 Triggering first CI run..."
        gh workflow run cache-observation.yml --repo "$REPO_URL"
        
        # Wait for the run to start
        echo "⏳ Waiting for workflow to start..."
        sleep 10
        
        # Get the most recent run and wait for it to complete
        run_id=$(gh run list --workflow=cache-observation.yml --limit=1 --json databaseId --jq '.[0].databaseId' --repo "$REPO_URL")
        echo "📊 Monitoring run $run_id..."
        
        # Wait for completion
        gh run watch "$run_id" --exit-status --repo "$REPO_URL"
        
        # Get logs for first run
        echo "📥 Downloading logs from first run..."
        gh run view "$run_id" --log --repo "$REPO_URL" > "$log_dir/run1.log" 2>&1
        
        echo "📋 Triggering second CI run..."
        gh workflow run cache-observation.yml --repo "$REPO_URL"
        
        # Wait for the second run to start
        echo "⏳ Waiting for second workflow to start..."
        sleep 10
        
        # Get the most recent run and wait for it to complete
        run_id2=$(gh run list --workflow=cache-observation.yml --limit=1 --json databaseId --jq '.[0].databaseId' --repo "$REPO_URL")
        echo "📊 Monitoring run $run_id2..."
        
        # Wait for completion
        gh run watch "$run_id2" --exit-status --repo "$REPO_URL"
        
        # Get logs for second run
        echo "📥 Downloading logs from second run..."
        gh run view "$run_id2" --log --repo "$REPO_URL" > "$log_dir/run2.log" 2>&1
        
        # Analyze cache behavior
        echo ""
        echo "🔍 CACHE BEHAVIOR ANALYSIS"
        echo "========================="
        
        # Count cache operations
        run1_downloads=$(grep -c "copying path.*from.*cache.nixos.org" "$log_dir/run1.log" || echo "0")
        run1_builds=$(grep -c "^building" "$log_dir/run1.log" || echo "0")
        
        run2_downloads=$(grep -c "copying path.*from.*cache.nixos.org" "$log_dir/run2.log" || echo "0")
        run2_builds=$(grep -c "^building" "$log_dir/run2.log" || echo "0")
        
        echo "Run 1 - Downloads from cache.nixos.org: $run1_downloads"
        echo "Run 1 - Local builds: $run1_builds"
        echo "Run 2 - Downloads from cache.nixos.org: $run2_downloads"
        echo "Run 2 - Local builds: $run2_builds"
        echo ""
        
        # Show differences in cache operations
        echo "🔄 CACHE OPERATION DIFFERENCES"
        echo "=============================="
        
        # Extract cache operations from both runs
        grep "copying path.*from.*cache.nixos.org" "$log_dir/run1.log" | sort > "$log_dir/run1_cache.txt" || touch "$log_dir/run1_cache.txt"
        grep "copying path.*from.*cache.nixos.org" "$log_dir/run2.log" | sort > "$log_dir/run2_cache.txt" || touch "$log_dir/run2_cache.txt"
        
        echo "Cache operations only in Run 1:"
        comm -23 "$log_dir/run1_cache.txt" "$log_dir/run2_cache.txt" | head -10
        
        echo ""
        echo "Cache operations only in Run 2:"
        comm -13 "$log_dir/run1_cache.txt" "$log_dir/run2_cache.txt" | head -10
        
        echo ""
        echo "Common cache operations:"
        comm -12 "$log_dir/run1_cache.txt" "$log_dir/run2_cache.txt" | wc -l | xargs echo "Count:"
        
        # Show build differences
        echo ""
        echo "🔨 BUILD OPERATION DIFFERENCES"
        echo "=============================="
        
        # Extract build operations from both runs
        grep "^building" "$log_dir/run1.log" | sort > "$log_dir/run1_builds.txt" || touch "$log_dir/run1_builds.txt"
        grep "^building" "$log_dir/run2.log" | sort > "$log_dir/run2_builds.txt" || touch "$log_dir/run2_builds.txt"
        
        echo "Builds only in Run 1:"
        comm -23 "$log_dir/run1_builds.txt" "$log_dir/run2_builds.txt" | head -10
        
        echo ""
        echo "Builds only in Run 2:"
        comm -13 "$log_dir/run1_builds.txt" "$log_dir/run2_builds.txt" | head -10
        
        # Analyze if caching is working
        echo ""
        echo "📈 CACHE EFFECTIVENESS ANALYSIS"
        echo "==============================="
        
        if [ "$run2_downloads" -lt "$run1_downloads" ]; then
          echo "✅ Good: Run 2 downloaded fewer items from cache.nixos.org ($run2_downloads vs $run1_downloads)"
          echo "   This suggests GitHub Actions caching is working effectively"
        else
          echo "⚠️  Warning: Run 2 downloaded same or more items from cache.nixos.org ($run2_downloads vs $run1_downloads)"
          echo "   This might indicate GitHub Actions caching is not working as expected"
        fi
        
        if [ "$run2_builds" -lt "$run1_builds" ]; then
          echo "✅ Good: Run 2 had fewer local builds ($run2_builds vs $run1_builds)"
          echo "   This suggests derivation caching is working effectively"
        else
          echo "⚠️  Warning: Run 2 had same or more local builds ($run2_builds vs $run1_builds)"
          echo "   This might indicate derivation caching is not working as expected"
        fi
        
        echo ""
        echo "🎯 Analysis complete! Check the logs above for detailed cache behavior."
      '';

      verboseCommand = ''
        set -euo pipefail
        
        echo "🧪 Starting CI cache behavior analysis (VERBOSE MODE)..."
        echo "Using checkdef-demo from: ${checkdefDemoEnvPath}"
        
        # Instead of cd into nix store, use the repo URL directly
        REPO_URL="MatrixManAtYrService/checkdef-demo"
        
        # Check if we have the gh CLI available
        if ! command -v gh &> /dev/null; then
          echo "❌ GitHub CLI (gh) is required for CI analysis"
          echo "Please install it: https://cli.github.com/"
          exit 1
        fi
        
        # Check if we're authenticated with GitHub
        if ! gh auth status &> /dev/null; then
          echo "❌ Not authenticated with GitHub"
          echo "Please run: gh auth login"
          exit 1
        fi
        
        # Create temporary directory for logs
        log_dir=$(mktemp -d)
        trap 'rm -rf "$log_dir"' EXIT
        
        echo "📋 Triggering first CI run..."
        gh workflow run cache-observation.yml --repo "$REPO_URL"
        
        # Wait for the run to start
        echo "⏳ Waiting for workflow to start..."
        sleep 10
        
        # Get the most recent run and wait for it to complete
        run_id=$(gh run list --workflow=cache-observation.yml --limit=1 --json databaseId --jq '.[0].databaseId' --repo "$REPO_URL")
        echo "📊 Monitoring run $run_id..."
        
        # Wait for completion
        gh run watch "$run_id" --exit-status --repo "$REPO_URL"
        
        # Get logs for first run
        echo "📥 Downloading logs from first run..."
        gh run view "$run_id" --log --repo "$REPO_URL" > "$log_dir/run1.log" 2>&1
        
        echo "📋 Triggering second CI run..."
        gh workflow run cache-observation.yml --repo "$REPO_URL"
        
        # Wait for the second run to start
        echo "⏳ Waiting for second workflow to start..."
        sleep 10
        
        # Get the most recent run and wait for it to complete
        run_id2=$(gh run list --workflow=cache-observation.yml --limit=1 --json databaseId --jq '.[0].databaseId' --repo "$REPO_URL")
        echo "📊 Monitoring run $run_id2..."
        
        # Wait for completion
        gh run watch "$run_id2" --exit-status --repo "$REPO_URL"
        
        # Get logs for second run
        echo "📥 Downloading logs from second run..."
        gh run view "$run_id2" --log --repo "$REPO_URL" > "$log_dir/run2.log" 2>&1
        
        # In verbose mode, show full logs
        echo ""
        echo "📋 FULL LOGS FROM RUN 1"
        echo "======================="
        cat "$log_dir/run1.log"
        
        echo ""
        echo "📋 FULL LOGS FROM RUN 2"
        echo "======================="
        cat "$log_dir/run2.log"
        
        # Analyze cache behavior (same as regular command)
        echo ""
        echo "🔍 CACHE BEHAVIOR ANALYSIS"
        echo "========================="
        
        # Count cache operations
        run1_downloads=$(grep -c "copying path.*from.*cache.nixos.org" "$log_dir/run1.log" || echo "0")
        run1_builds=$(grep -c "^building" "$log_dir/run1.log" || echo "0")
        
        run2_downloads=$(grep -c "copying path.*from.*cache.nixos.org" "$log_dir/run2.log" || echo "0")
        run2_builds=$(grep -c "^building" "$log_dir/run2.log" || echo "0")
        
        echo "Run 1 - Downloads from cache.nixos.org: $run1_downloads"
        echo "Run 1 - Local builds: $run1_builds"
        echo "Run 2 - Downloads from cache.nixos.org: $run2_downloads"
        echo "Run 2 - Local builds: $run2_builds"
        echo ""
        
        # Show differences in cache operations
        echo "🔄 CACHE OPERATION DIFFERENCES"
        echo "=============================="
        
        # Extract cache operations from both runs
        grep "copying path.*from.*cache.nixos.org" "$log_dir/run1.log" | sort > "$log_dir/run1_cache.txt" || touch "$log_dir/run1_cache.txt"
        grep "copying path.*from.*cache.nixos.org" "$log_dir/run2.log" | sort > "$log_dir/run2_cache.txt" || touch "$log_dir/run2_cache.txt"
        
        echo "Cache operations only in Run 1:"
        comm -23 "$log_dir/run1_cache.txt" "$log_dir/run2_cache.txt"
        
        echo ""
        echo "Cache operations only in Run 2:"
        comm -13 "$log_dir/run1_cache.txt" "$log_dir/run2_cache.txt"
        
        echo ""
        echo "Common cache operations:"
        comm -12 "$log_dir/run1_cache.txt" "$log_dir/run2_cache.txt"
        
        # Show build differences
        echo ""
        echo "🔨 BUILD OPERATION DIFFERENCES"
        echo "=============================="
        
        # Extract build operations from both runs
        grep "^building" "$log_dir/run1.log" | sort > "$log_dir/run1_builds.txt" || touch "$log_dir/run1_builds.txt"
        grep "^building" "$log_dir/run2.log" | sort > "$log_dir/run2_builds.txt" || touch "$log_dir/run2_builds.txt"
        
        echo "Builds only in Run 1:"
        comm -23 "$log_dir/run1_builds.txt" "$log_dir/run2_builds.txt"
        
        echo ""
        echo "Builds only in Run 2:"
        comm -13 "$log_dir/run1_builds.txt" "$log_dir/run2_builds.txt"
        
        # Analyze if caching is working
        echo ""
        echo "📈 CACHE EFFECTIVENESS ANALYSIS"
        echo "==============================="
        
        if [ "$run2_downloads" -lt "$run1_downloads" ]; then
          echo "✅ Good: Run 2 downloaded fewer items from cache.nixos.org ($run2_downloads vs $run1_downloads)"
          echo "   This suggests GitHub Actions caching is working effectively"
        else
          echo "⚠️  Warning: Run 2 downloaded same or more items from cache.nixos.org ($run2_downloads vs $run1_downloads)"
          echo "   This might indicate GitHub Actions caching is not working as expected"
        fi
        
        if [ "$run2_builds" -lt "$run1_builds" ]; then
          echo "✅ Good: Run 2 had fewer local builds ($run2_builds vs $run1_builds)"
          echo "   This suggests derivation caching is working effectively"
        else
          echo "⚠️  Warning: Run 2 had same or more local builds ($run2_builds vs $run1_builds)"
          echo "   This might indicate derivation caching is not working as expected"
        fi
        
        echo ""
        echo "🎯 Analysis complete! Check the logs above for detailed cache behavior."
      '';

      dependencies = [ pkgs.github-cli pkgs.jq ];

      environment = defaultEnvironment // {
        CHECKDEF_DEMO_PATH = "${checkdefDemoEnvPath}";
      };
    };

in
{
  inherit pattern;
} 