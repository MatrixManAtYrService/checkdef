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
- Verbose flag controls logging output
- Timing display works correctly for different check types

Optimized fixture design:
- cached_main_commands: Performance and timing display tests (1 container)
- cached_verbose_commands: Verbose flag behavior tests (1 container)  
- cached_invalidation_commands: Cache invalidation tests (1 container)
  * Separate container needed to maintain cache independence for proper invalidation testing
  * Consolidated approach broke selective invalidation due to shared cache dependencies
"""

import subprocess
import tempfile
import time
import os
import re
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Tuple, Optional, List

import pytest


@dataclass
class TimedCommand:
    """Represents a timed command execution with its results."""
    command: str
    exit_code: int
    output: str
    duration: float
    
    @property
    def succeeded(self) -> bool:
        """Whether the command succeeded (exit code 0)."""
        return self.exit_code == 0
    
    def contains_log(self, text: str) -> bool:
        """Check if the command output contains specific text."""
        return text in self.output
    
    def contains_log_pattern(self, pattern: str) -> bool:
        """Check if the command output matches a regex pattern."""
        return bool(re.search(pattern, self.output))


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
        
        # Build the image - use --load to ensure it's loaded into local Docker daemon
        build_cmd = [
            self.container_tool, "build", 
            "--load",  # Load the image into Docker daemon
            "-t", image_tag,
            str(build_context)
        ]
        
        print(f"🐳 Building Docker image: {image_tag}")
        result = subprocess.run(build_cmd, capture_output=True, text=True)
        
        if result.returncode != 0:
            pytest.fail(f"Failed to build Docker image {image_tag}: {result.stderr}")
            
        print(f"✅ Docker image built successfully: {image_tag}")
            
        # Start container using the tag (much simpler and more reliable)
        run_cmd = [
            self.container_tool, "run", "-d",  # detached mode
            "-w", "/workspace/checkdef-demo",  # working directory
            image_tag,  # Use the tag directly
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
        
    def run_timed_command(self, command: str) -> TimedCommand:
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
        
        return TimedCommand(
            command=command,
            exit_code=result.returncode,
            output=result.stdout + result.stderr,
            duration=duration
        )
        
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


@pytest.fixture(scope="session")
def cached_main_commands(workspace_root, checkdef_demo_path, container_tool):
    """Run main test commands for performance and timing display tests."""
    container = CheckdefTestContainer(workspace_root, checkdef_demo_path, container_tool)
    container.start_container()
    
    commands = {}
    
    try:
        print("🧪 Running main test commands...")
        
        # Performance test sequence (must be first to preserve cache states)
        print("📊 Running uncached foo...")
        commands['uncached_foo'] = container.run_timed_command("nix run .#checklist-foo")
        
        print("📊 Running first bar...")
        commands['first_bar'] = container.run_timed_command("nix run .#checklist-bar")
        
        print("📊 Running partially cached foo...")
        commands['partially_cached_foo'] = container.run_timed_command("nix run .#checklist-foo")
        
        print("📊 Running fully cached foo...")
        commands['fully_cached_foo'] = container.run_timed_command("nix run .#checklist-foo")
        
        print("📊 Running cached bar...")
        commands['cached_bar'] = container.run_timed_command("nix run .#checklist-bar")
        
        # Timing display test commands (after cache is warmed up)
        print("📊 Running script-based linters...")
        commands['script_check'] = container.run_timed_command("nix run .#checklist-linters")
        
        print("📊 Running mixed checklist-all...")
        commands['mixed_check'] = container.run_timed_command("nix run .#checklist-all")
        
        print(f"✅ Completed {len(commands)} main test commands")
        
    finally:
        container.cleanup()
    
    return commands


@pytest.fixture(scope="session")
def cached_invalidation_commands(workspace_root, checkdef_demo_path, container_tool):
    """Run invalidation test commands (separate container needed for cache independence)."""
    container = CheckdefTestContainer(workspace_root, checkdef_demo_path, container_tool)
    container.start_container()
    
    commands = {}
    
    try:
        print("🧪 Running invalidation test commands...")
        
        # Populate both caches independently
        print("📊 Populating foo cache...")
        commands['initial_foo'] = container.run_timed_command("nix run .#checklist-foo")
        
        print("📊 Populating bar cache...")
        commands['initial_bar'] = container.run_timed_command("nix run .#checklist-bar")
        
        # Get baseline cached performance
        print("📊 Getting foo baseline...")
        commands['baseline_foo'] = container.run_timed_command("nix run .#checklist-foo")
        
        # Modify bar module
        print("📊 Modifying bar module...")
        commands['change_bar'] = container.run_timed_command("echo '# timestamp change' >> src/bar/__init__.py")
        
        # Test foo after bar change (should still be fast)
        print("📊 Testing foo after bar change...")
        commands['post_change_foo'] = container.run_timed_command("nix run .#checklist-foo")
        
        # Test bar after change (should rebuild)
        print("📊 Testing bar after change...")
        commands['post_change_bar'] = container.run_timed_command("nix run .#checklist-bar")
        
        print(f"✅ Completed {len(commands)} invalidation test commands")
        
    finally:
        container.cleanup()
    
    return commands


@pytest.fixture(scope="session") 
def cached_verbose_commands(workspace_root, checkdef_demo_path, container_tool):
    """Run commands with and without verbose flag to test logging behavior."""
    container = CheckdefTestContainer(workspace_root, checkdef_demo_path, container_tool)
    container.start_container()
    
    commands = {}
    
    try:
        print("🧪 Running verbose test commands...")
        
        # Run foo commands with and without verbose flag
        print("📊 Running foo without verbose...")
        commands['foo_normal'] = container.run_timed_command("nix run .#checklist-foo")
        
        print("📊 Running foo with verbose...")
        commands['foo_verbose'] = container.run_timed_command("nix run .#checklist-foo -- -v")
        
        # Run bar commands with and without verbose flag
        print("📊 Running bar without verbose...")
        commands['bar_normal'] = container.run_timed_command("nix run .#checklist-bar")
        
        print("📊 Running bar with verbose...")
        commands['bar_verbose'] = container.run_timed_command("nix run .#checklist-bar -- -v")
        
        print(f"✅ Completed {len(commands)} verbose test commands")
        
    finally:
        container.cleanup()
    
    return commands


class TestCacheBehavior:
    """Test checkdef's selective caching behavior."""
    
    @pytest.mark.integration
    @pytest.mark.container
    def test_selective_caching_performance(self, cached_main_commands):
        """Test that selective caching provides expected performance improvements."""
        
        # Extract relevant command results
        uncached_foo = cached_main_commands['uncached_foo']
        first_bar = cached_main_commands['first_bar']
        partially_cached_foo = cached_main_commands['partially_cached_foo']
        fully_cached_foo = cached_main_commands['fully_cached_foo']
        cached_bar = cached_main_commands['cached_bar']
        
        # Verify all commands succeeded
        assert uncached_foo.succeeded, f"Uncached foo run failed: {uncached_foo.output}"
        assert first_bar.succeeded, f"First bar run failed: {first_bar.output}"
        assert partially_cached_foo.succeeded, f"Partially cached foo run failed: {partially_cached_foo.output}"
        assert fully_cached_foo.succeeded, f"Fully cached foo run failed: {fully_cached_foo.output}"
        assert cached_bar.succeeded, f"Cached bar run failed: {cached_bar.output}"
        
        # Performance assertions
        print(f"📈 Performance comparison:")
        print(f"   Uncached: {uncached_foo.duration:.3f}s")
        print(f"   Partially cached: {partially_cached_foo.duration:.3f}s")
        print(f"   Fully cached: {fully_cached_foo.duration:.3f}s")
        
        # Allow some tolerance for timing variations
        # Uncached should be significantly slower than partially cached
        assert uncached_foo.duration > partially_cached_foo.duration * 1.2, \
            f"Expected uncached ({uncached_foo.duration:.3f}s) > partially cached ({partially_cached_foo.duration:.3f}s) * 1.2"
            
        # Partially cached should be slower than fully cached
        assert partially_cached_foo.duration > fully_cached_foo.duration * 1.1, \
            f"Expected partially cached ({partially_cached_foo.duration:.3f}s) > fully cached ({fully_cached_foo.duration:.3f}s) * 1.1"
            
        print("✅ Cache behavior validation passed!")
        
    @pytest.mark.integration
    @pytest.mark.container
    def test_selective_invalidation(self, cached_invalidation_commands):
        """Test that changes to one module don't invalidate cache for another."""
        
        # Extract command results
        initial_foo = cached_invalidation_commands['initial_foo']
        initial_bar = cached_invalidation_commands['initial_bar']
        baseline_foo = cached_invalidation_commands['baseline_foo']
        change_bar = cached_invalidation_commands['change_bar']
        post_change_foo = cached_invalidation_commands['post_change_foo']
        post_change_bar = cached_invalidation_commands['post_change_bar']
        
        # Verify all commands succeeded
        assert initial_foo.succeeded, f"Initial foo run failed: {initial_foo.output}"
        assert initial_bar.succeeded, f"Initial bar run failed: {initial_bar.output}"
        assert baseline_foo.succeeded, f"Baseline foo run failed: {baseline_foo.output}"
        assert change_bar.succeeded, f"Bar change failed: {change_bar.output}"
        assert post_change_foo.succeeded, f"Post-change foo run failed: {post_change_foo.output}"
        assert post_change_bar.succeeded, f"Post-change bar run failed: {post_change_bar.output}"
        
        print(f"📈 Selective invalidation results:")
        print(f"   Initial foo (uncached): {initial_foo.duration:.3f}s")
        print(f"   Initial bar (uncached): {initial_bar.duration:.3f}s")
        print(f"   Foo baseline (cached): {baseline_foo.duration:.3f}s")
        print(f"   Foo after bar change: {post_change_foo.duration:.3f}s") 
        print(f"   Bar after change: {post_change_bar.duration:.3f}s")
        
        # Define what constitutes a "fast" cached run vs "slow" uncached run
        # Fast cached runs should be under 5 seconds, slow uncached runs should be over 15 seconds
        FAST_CACHE_THRESHOLD = 5.0  # seconds
        SLOW_BUILD_THRESHOLD = 15.0  # seconds
        
        # Foo should remain fast after bar changes (cache not invalidated)
        # This is the key test - foo should stay under the fast threshold
        assert post_change_foo.duration < FAST_CACHE_THRESHOLD, \
            f"SELECTIVE CACHING BROKEN: Foo cache was invalidated by bar change. " \
            f"Expected foo to remain fast (< {FAST_CACHE_THRESHOLD}s) but took {post_change_foo.duration:.3f}s. " \
            f"This indicates shared cache dependencies between foo and bar modules."
            
        # Bar should be slow after its own change (cache invalidated)
        assert post_change_bar.duration > SLOW_BUILD_THRESHOLD, \
            f"Bar cache was not invalidated by its own change: {post_change_bar.duration:.3f}s (expected > {SLOW_BUILD_THRESHOLD}s)"
            
        # Additional validation: baseline foo should also be fast (sanity check)
        assert baseline_foo.duration < FAST_CACHE_THRESHOLD, \
            f"Baseline foo should be fast (cached) but took {baseline_foo.duration:.3f}s. " \
            f"This suggests the cache setup is broken."
            
        print("✅ Selective invalidation validation passed!")
        
    @pytest.mark.integration
    @pytest.mark.container
    def test_verbose_logging_behavior(self, cached_verbose_commands):
        """Test that verbose flag controls logging output."""
        
        # Extract command results
        foo_normal = cached_verbose_commands['foo_normal']
        foo_verbose = cached_verbose_commands['foo_verbose']
        bar_normal = cached_verbose_commands['bar_normal']
        bar_verbose = cached_verbose_commands['bar_verbose']
        
        # Verify all commands succeeded
        assert foo_normal.succeeded, f"Foo normal run failed: {foo_normal.output}"
        assert foo_verbose.succeeded, f"Foo verbose run failed: {foo_verbose.output}"
        assert bar_normal.succeeded, f"Bar normal run failed: {bar_normal.output}"
        assert bar_verbose.succeeded, f"Bar verbose run failed: {bar_verbose.output}"
        
        print("🧪 Testing verbose logging behavior...")
        
        # Non-verbose runs should NOT contain "Nix build command:"
        assert not foo_normal.contains_log("Nix build command:"), \
            f"Non-verbose foo should not show 'Nix build command:' but output contains: {foo_normal.output[:500]}"
        assert not bar_normal.contains_log("Nix build command:"), \
            f"Non-verbose bar should not show 'Nix build command:' but output contains: {bar_normal.output[:500]}"
        
        # Verbose runs SHOULD contain "Nix build command:"
        assert foo_verbose.contains_log("Nix build command:"), \
            f"Verbose foo should show 'Nix build command:' but output does not contain it: {foo_verbose.output[:500]}"
        assert bar_verbose.contains_log("Nix build command:"), \
            f"Verbose bar should show 'Nix build command:' but output does not contain it: {bar_verbose.output[:500]}"
        
        print("✅ Verbose logging validation passed!")
        
    @pytest.mark.integration
    @pytest.mark.container
    def test_build_log_content(self, cached_verbose_commands):
        """Test that build logs contain expected content."""
        
        # Extract command results
        foo_normal = cached_verbose_commands['foo_normal']
        foo_verbose = cached_verbose_commands['foo_verbose']
        bar_normal = cached_verbose_commands['bar_normal']
        bar_verbose = cached_verbose_commands['bar_verbose']
        
        # Verify all commands succeeded
        assert foo_normal.succeeded, f"Foo normal run failed: {foo_normal.output}"
        assert foo_verbose.succeeded, f"Foo verbose run failed: {foo_verbose.output}"
        assert bar_normal.succeeded, f"Bar normal run failed: {bar_normal.output}"
        assert bar_verbose.succeeded, f"Bar verbose run failed: {bar_verbose.output}"
        
        print("🧪 Testing build log content...")
        
        # All runs should contain "All checks passed!" indicating successful completion
        for cmd in [foo_normal, foo_verbose, bar_normal, bar_verbose]:
            assert cmd.contains_log("All checks passed!"), \
                f"Command {cmd.command} should contain 'All checks passed!' but output: {cmd.output[-500:]}"
        
        # Verbose runs should contain more detailed information
        assert foo_verbose.contains_log("Underlying command:"), \
            f"Verbose foo should show 'Underlying command:' but output: {foo_verbose.output[:500]}"
        assert bar_verbose.contains_log("Underlying command:"), \
            f"Verbose bar should show 'Underlying command:' but output: {bar_verbose.output[:500]}"
        
        # Verbose runs should show pytest execution details
        assert foo_verbose.contains_log_pattern(r"pytest.*tests/test_foo\.py"), \
            f"Verbose foo should show pytest command but output: {foo_verbose.output[:500]}"
        assert bar_verbose.contains_log_pattern(r"pytest.*tests/test_bar\.py"), \
            f"Verbose bar should show pytest command but output: {bar_verbose.output[:500]}"
        
        print("✅ Build log content validation passed!")
        
    @pytest.mark.integration
    @pytest.mark.container
    def test_derivation_timing_display(self, cached_main_commands):
        """Test that derivation-based checks show timing information when cached."""
        
        # Extract relevant command results
        script_check = cached_main_commands['script_check']
        fully_cached_foo = cached_main_commands['fully_cached_foo']
        cached_bar = cached_main_commands['cached_bar']
        mixed_check = cached_main_commands['mixed_check']
        
        # Verify all commands succeeded
        assert script_check.succeeded, f"Script check failed: {script_check.output}"
        assert fully_cached_foo.succeeded, f"Fully cached foo run failed: {fully_cached_foo.output}"
        assert cached_bar.succeeded, f"Cached bar run failed: {cached_bar.output}"
        assert mixed_check.succeeded, f"Mixed check failed: {mixed_check.output}"
        
        print("🧪 Testing derivation timing display...")
        
        # Cached derivation runs should show timing information
        # Derivation-based checks with historical timing data show dual timing like "(original: 10.017s reference: 0.067s)"
        # OR single timing like "(0.804s)" for fast cached runs without historical data
        dual_timing_pattern = r'\(original: \d+\.\d+s reference: \d+\.\d+s\)'
        single_timing_pattern = r'\(\d+\.\d+s\)'
        
        # Verify cached runs show timing information (either dual or single)
        has_dual_timing = fully_cached_foo.contains_log_pattern(dual_timing_pattern)
        has_single_timing = fully_cached_foo.contains_log_pattern(single_timing_pattern)
        
        assert has_dual_timing or has_single_timing, \
            f"Cached foo should show timing information but output: {fully_cached_foo.output[:1000]}"
        
        # Verify mixed checks show timing information for all components
        mixed_has_dual = mixed_check.contains_log_pattern(dual_timing_pattern)
        mixed_has_single = mixed_check.contains_log_pattern(single_timing_pattern)
        
        assert mixed_has_dual or mixed_has_single, \
            f"Mixed check should show timing information but output: {mixed_check.output[:1000]}"
        
        print("✅ Derivation timing display validation passed!")
        
    @pytest.mark.integration
    @pytest.mark.container
    def test_script_timing_display(self, cached_main_commands):
        """Test that script-based checks show single timing value."""
        
        # Extract relevant command results  
        script_check = cached_main_commands['script_check']
        mixed_check = cached_main_commands['mixed_check']
        
        # Verify all commands succeeded
        assert script_check.succeeded, f"Script check failed: {script_check.output}"
        assert mixed_check.succeeded, f"Mixed check failed: {mixed_check.output}"
        
        print("🧪 Testing script timing display...")
        
        # Script-based checks should show single timing pattern like "(0.067s)"
        single_timing_pattern = r'\(\d+\.\d+s\)(?!\s+reference:)'  # Duration but not followed by "reference:"
        
        assert script_check.contains_log_pattern(single_timing_pattern), \
            f"Script check should show single timing but output: {script_check.output[:1000]}"
        
        # In mixed checks, script parts should still show single timing
        # Look for ruff checks that should have single timing
        ruff_lines = [line for line in mixed_check.output.split('\n') if 'ruff' in line.lower() and 'PASSED' in line]
        
        for line in ruff_lines:
            assert not 'original:' in line, \
                f"Script-based ruff check should not show original timing but line: {line}"
            assert 'PASSED (' in line, \
                f"Script-based ruff check should show single timing but line: {line}"
        
        print("✅ Script timing display validation passed!") 