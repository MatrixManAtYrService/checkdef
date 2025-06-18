"""
Cache behavior validation tests for checkdef.

This test suite validates checkdef's selective caching behavior by:
1. Running checkdef-demo commands in containers
2. Measuring execution times across different cache states
3. Asserting that caching provides the expected performance improvements

The tests verify that:
- Uncached runs take longer than partially cached runs
- Partially cached runs take longer than fully cached runs
- Selective caching works (foo changes don't invalidate bar cache)
"""

import subprocess
import tempfile
import time
import os
import re
import shutil
from pathlib import Path
from typing import Tuple, Optional

import pytest


class CheckdefTestContainer:
    """Helper class to manage checkdef test containers."""
    
    def __init__(self, workspace_root: Path, checkdef_demo_path: Path, container_tool: str):
        self.workspace_root = workspace_root
        self.checkdef_demo_path = checkdef_demo_path
        self.container_tool = container_tool
        self.container_id: Optional[str] = None
        self.build_context_dir: Optional[Path] = None
        
    def prepare_build_context(self) -> Path:
        """Prepare build context with checkdef and checkdef-demo."""
        if self.build_context_dir:
            return self.build_context_dir
            
        print("🔧 Preparing Docker build context...")
        
        # Create temporary build context
        self.build_context_dir = Path(tempfile.mkdtemp(prefix="checkdef-test-"))
        
        # Copy checkdef (current repo, excluding .git and result directories)
        checkdef_dest = self.build_context_dir / "checkdef"
        print(f"📁 Copying checkdef to {checkdef_dest}")
        shutil.copytree(
            self.workspace_root, 
            checkdef_dest,
            ignore=shutil.ignore_patterns('.git', 'result*', '.direnv', '__pycache__', '*.pyc')
        )
        
        # Copy checkdef-demo from flake input
        checkdef_demo_dest = self.build_context_dir / "checkdef-demo"
        print(f"📁 Copying checkdef-demo to {checkdef_demo_dest}")
        shutil.copytree(
            self.checkdef_demo_path, 
            checkdef_demo_dest,
            ignore=shutil.ignore_patterns('.git', 'result*', '.direnv', '__pycache__', '*.pyc')
        )
        
        # Copy Dockerfile
        dockerfile_src = self.workspace_root / "tests" / "docker" / "Dockerfile"
        dockerfile_dest = self.build_context_dir / "Dockerfile"
        shutil.copy2(dockerfile_src, dockerfile_dest)
        
        print(f"✅ Build context prepared at {self.build_context_dir}")
        return self.build_context_dir
        
    def start_container(self) -> str:
        """Build and start the container."""
        if self.container_id:
            return self.container_id
            
        build_context = self.prepare_build_context()
        image_tag = "checkdef-test"
        
        # Build the image
        build_cmd = [
            self.container_tool, "build", 
            "-t", image_tag,
            str(build_context)
        ]
        
        print(f"🐳 Building Docker image: {image_tag}")
        result = subprocess.run(build_cmd, capture_output=True, text=True)
        
        if result.returncode != 0:
            pytest.fail(f"Failed to build Docker image {image_tag}: {result.stderr}")
            
        # Extract image hash from build output
        image_hash = None
        build_output = result.stdout + result.stderr
        
        # Debug: show actual build output to understand the format
        print(f"🔍 Build output sample: {build_output[-500:]}")  # Last 500 chars
        
        # Look for image hash in different formats
        patterns = [
            # New buildkit format variations
            r'writing image sha256:([a-f0-9]{64})',
            r'=> => writing image sha256:([a-f0-9]{64})',
            # Old format
            r'Successfully built ([a-f0-9]{12})',
            # Alternative patterns
            r'sha256:([a-f0-9]{64})',
        ]
        
        for pattern in patterns:
            hash_match = re.search(pattern, build_output)
            if hash_match:
                if len(hash_match.group(1)) == 64:
                    image_hash = f"sha256:{hash_match.group(1)}"
                else:
                    image_hash = hash_match.group(1)
                print(f"✅ Found image hash using pattern '{pattern}': {image_hash}")
                break
        
        if not image_hash:
            # Try to get the image ID directly after build
            list_cmd = [self.container_tool, "images", "-q", image_tag]
            list_result = subprocess.run(list_cmd, capture_output=True, text=True)
            if list_result.returncode == 0 and list_result.stdout.strip():
                image_hash = list_result.stdout.strip()
                print(f"✅ Retrieved image hash from docker images: {image_hash}")
        
        if not image_hash:
            # Final fallback to tag
            print("⚠️  Could not extract image hash, falling back to tag")
            image_reference = image_tag
        else:
            image_reference = image_hash
            
        # Start container using image hash or tag
        run_cmd = [
            self.container_tool, "run", "-d",  # detached mode
            "-w", "/workspace/checkdef-demo",  # working directory
            image_reference,
            "tail", "-f", "/dev/null"  # Keep container running
        ]
        
        print(f"🚀 Starting container...")
        result = subprocess.run(run_cmd, capture_output=True, text=True)
        
        if result.returncode != 0:
            pytest.fail(f"Failed to start container: {result.stderr}")
            
        self.container_id = result.stdout.strip()
        print(f"✅ Container started: {self.container_id}")
        
        # Wait for container to be ready
        time.sleep(2)
        
        return self.container_id
        
    def run_timed_command(self, command: str) -> Tuple[int, str, float]:
        """Run a command in the container and measure execution time."""
        if not self.container_id:
            pytest.fail("Container not started")
            
        print(f"⏱️  Running timed command: {command}")
        
        start_time = time.time()
        
        exec_cmd = [
            self.container_tool, "exec", 
            self.container_id,
            "bash", "-c", command
        ]
        
        result = subprocess.run(exec_cmd, capture_output=True, text=True)
        
        end_time = time.time()
        duration = end_time - start_time
        
        print(f"🏁 Command completed in {duration:.3f}s with exit code: {result.returncode}")
        
        return result.returncode, result.stdout + result.stderr, duration
        
    def stop_container(self):
        """Stop and remove the container."""
        if self.container_id:
            try:
                # Stop the container
                subprocess.run([self.container_tool, "stop", self.container_id], 
                             capture_output=True, text=True, timeout=30)
                # Remove the container
                subprocess.run([self.container_tool, "rm", self.container_id], 
                             capture_output=True, text=True, timeout=30)
                print(f"✅ Container {self.container_id} stopped and removed")
            except Exception as e:
                print(f"⚠️  Error stopping container: {e}")
            finally:
                self.container_id = None
                
    def cleanup(self):
        """Clean up container and build context."""
        self.stop_container()
        if self.build_context_dir and self.build_context_dir.exists():
            shutil.rmtree(self.build_context_dir, ignore_errors=True)
            print(f"🧹 Cleaned up build context")


@pytest.fixture(scope="session")
def workspace_root():
    """Get the workspace root directory."""
    return Path(__file__).parent.parent


@pytest.fixture(scope="session")
def checkdef_demo_path():
    """Get checkdef-demo path from environment variable."""
    demo_path = os.environ.get("CHECKDEF_DEMO_PATH")
    if not demo_path:
        pytest.fail(
            "CHECKDEF_DEMO_PATH environment variable is not set. "
            "Please set it to the path of the checkdef-demo source."
        )
    demo_dir = Path(demo_path)
    if not demo_dir.exists():
        pytest.fail(f"CHECKDEF_DEMO_PATH does not exist: {demo_dir}")
    return demo_dir


@pytest.fixture(scope="session")
def container_tool():
    """Find and cache the available container tool (docker or podman)."""
    # Allow override via environment variable
    if "CONTAINER_TOOL" in os.environ:
        tool = os.environ["CONTAINER_TOOL"]
        try:
            result = subprocess.run([tool, "--version"], capture_output=True, text=True)
            if result.returncode == 0:
                print(f"✅ Found container tool (env): {tool}")
                return tool
        except Exception:
            pass

    # Common paths where docker/podman might be installed
    common_paths = [
        "/usr/bin", "/usr/local/bin", "/opt/homebrew/bin", 
        "/usr/sbin", "/usr/local/sbin", "/bin", "/sbin"
    ]

    for tool in ["docker", "podman"]:
        # First try from PATH
        try:
            result = subprocess.run([tool, "--version"], capture_output=True, text=True)
            if result.returncode == 0:
                print(f"✅ Found container tool: {tool}")
                return tool
        except FileNotFoundError:
            pass

        # Try common installation paths
        for path in common_paths:
            tool_path = os.path.join(path, tool)
            if os.path.exists(tool_path) and os.access(tool_path, os.X_OK):
                try:
                    result = subprocess.run([tool_path, "--version"], capture_output=True, text=True)
                    if result.returncode == 0:
                        print(f"✅ Found container tool: {tool_path}")
                        return tool_path
                except Exception:
                    continue

    pytest.fail("Neither docker nor podman found. Please install a container runtime.")


@pytest.fixture
def test_container(workspace_root, checkdef_demo_path, container_tool):
    """Create and manage a test container."""
    container = CheckdefTestContainer(workspace_root, checkdef_demo_path, container_tool)
    container.start_container()
    
    yield container
    
    container.cleanup()


class TestCacheBehavior:
    """Test checkdef's selective caching behavior."""
    
    @pytest.mark.integration
    @pytest.mark.container
    def test_selective_caching_performance(self, test_container):
        """Test that selective caching provides expected performance improvements."""
        
        # Scenario 1: Uncached run (fresh container)
        print("🧪 Testing uncached performance...")
        exit_code, output, uncached_duration = test_container.run_timed_command("nix run .#checklist-foo")
        assert exit_code == 0, f"Uncached foo run failed: {output}"
        print(f"📊 Uncached duration: {uncached_duration:.3f}s")
        
        # Scenario 2: Partially cached run (after running bar)
        print("🧪 Testing partially cached performance...")
        # First run bar to populate some shared dependencies
        exit_code, output, _ = test_container.run_timed_command("nix run .#checklist-bar")
        assert exit_code == 0, f"Bar run failed: {output}"
        
        # Now run foo again - should be faster due to shared dependencies
        exit_code, output, partially_cached_duration = test_container.run_timed_command("nix run .#checklist-foo")
        assert exit_code == 0, f"Partially cached foo run failed: {output}"
        print(f"📊 Partially cached duration: {partially_cached_duration:.3f}s")
        
        # Scenario 3: Fully cached run (run foo again immediately)
        print("🧪 Testing fully cached performance...")
        exit_code, output, fully_cached_duration = test_container.run_timed_command("nix run .#checklist-foo")
        assert exit_code == 0, f"Fully cached foo run failed: {output}"
        print(f"📊 Fully cached duration: {fully_cached_duration:.3f}s")
        
        # Performance assertions
        print(f"📈 Performance comparison:")
        print(f"   Uncached: {uncached_duration:.3f}s")
        print(f"   Partially cached: {partially_cached_duration:.3f}s")
        print(f"   Fully cached: {fully_cached_duration:.3f}s")
        
        # Allow some tolerance for timing variations
        # Uncached should be significantly slower than partially cached
        assert uncached_duration > partially_cached_duration * 1.2, \
            f"Expected uncached ({uncached_duration:.3f}s) > partially cached ({partially_cached_duration:.3f}s) * 1.2"
            
        # Partially cached should be slower than fully cached
        assert partially_cached_duration > fully_cached_duration * 1.1, \
            f"Expected partially cached ({partially_cached_duration:.3f}s) > fully cached ({fully_cached_duration:.3f}s) * 1.1"
            
        print("✅ Cache behavior validation passed!")
        
    @pytest.mark.integration
    @pytest.mark.container
    def test_selective_invalidation(self, test_container):
        """Test that changes to one module don't invalidate cache for another."""
        
        # Run both foo and bar to populate caches
        print("🧪 Populating caches...")
        exit_code, _, _ = test_container.run_timed_command("nix run .#checklist-foo")
        assert exit_code == 0, "Initial foo run failed"
        
        exit_code, _, _ = test_container.run_timed_command("nix run .#checklist-bar") 
        assert exit_code == 0, "Initial bar run failed"
        
        # Run foo again to get baseline cached performance
        exit_code, _, baseline_foo_duration = test_container.run_timed_command("nix run .#checklist-foo")
        assert exit_code == 0, "Baseline foo run failed"
        
        # Make a trivial change to bar module (this should not affect foo cache)
        print("🧪 Making change to bar module...")
        change_cmd = "echo '# timestamp change' >> src/bar/__init__.py"
        exit_code, output, _ = test_container.run_timed_command(change_cmd)
        assert exit_code == 0, f"Failed to modify bar: {output}"
        
        # Run foo again - should still be fast (cached)
        exit_code, _, post_change_foo_duration = test_container.run_timed_command("nix run .#checklist-foo")
        assert exit_code == 0, "Post-change foo run failed"
        
        # Run bar - should be slower (cache invalidated)
        exit_code, _, post_change_bar_duration = test_container.run_timed_command("nix run .#checklist-bar")
        assert exit_code == 0, "Post-change bar run failed"
        
        print(f"📈 Selective invalidation results:")
        print(f"   Foo baseline: {baseline_foo_duration:.3f}s")
        print(f"   Foo after bar change: {post_change_foo_duration:.3f}s") 
        print(f"   Bar after change: {post_change_bar_duration:.3f}s")
        
        # Foo should remain fast (cache not invalidated)
        assert post_change_foo_duration < baseline_foo_duration * 1.3, \
            f"Foo cache was invalidated by bar change: {post_change_foo_duration:.3f}s vs {baseline_foo_duration:.3f}s"
            
        # Bar should be slower (cache invalidated)
        assert post_change_bar_duration > baseline_foo_duration * 0.8, \
            f"Bar cache was not invalidated by change: {post_change_bar_duration:.3f}s"
            
        print("✅ Selective invalidation validation passed!") 