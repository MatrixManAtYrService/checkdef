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
def cached_performance_commands(workspace_root, checkdef_demo_path, container_tool):
    """Run all performance test commands and cache results."""
    container = CheckdefTestContainer(workspace_root, checkdef_demo_path, container_tool)
    container.start_container()
    
    commands = []
    
    try:
        print("🧪 Caching performance test commands...")
        
        # 1. Uncached foo run
        print("📊 Running uncached foo...")
        commands.append(container.run_timed_command("nix run .#checklist-foo"))
        
        # 2. First bar run (populates bar cache)
        print("📊 Running first bar...")
        commands.append(container.run_timed_command("nix run .#checklist-bar"))
        
        # 3. Partially cached foo run  
        print("📊 Running partially cached foo...")
        commands.append(container.run_timed_command("nix run .#checklist-foo"))
        
        # 4. Fully cached foo run
        print("📊 Running fully cached foo...")
        commands.append(container.run_timed_command("nix run .#checklist-foo"))
        
        # 5. Cached bar run
        print("📊 Running cached bar...")
        commands.append(container.run_timed_command("nix run .#checklist-bar"))
        
        print(f"✅ Cached {len(commands)} performance commands")
        
    finally:
        container.cleanup()
    
    return commands


@pytest.fixture(scope="session") 
def cached_verbose_commands(workspace_root, checkdef_demo_path, container_tool):
    """Run commands with and without verbose flag and cache results."""
    container = CheckdefTestContainer(workspace_root, checkdef_demo_path, container_tool)
    container.start_container()
    
    commands = []
    
    try:
        print("🧪 Caching verbose test commands...")
        
        # Run without verbose flag
        print("📊 Running foo without verbose...")
        commands.append(container.run_timed_command("nix run .#checklist-foo"))
        
        # Run with verbose flag
        print("📊 Running foo with verbose...")
        commands.append(container.run_timed_command("nix run .#checklist-foo -- -v"))
        
        # Run bar without verbose flag
        print("📊 Running bar without verbose...")
        commands.append(container.run_timed_command("nix run .#checklist-bar"))
        
        # Run bar with verbose flag
        print("📊 Running bar with verbose...")
        commands.append(container.run_timed_command("nix run .#checklist-bar -- -v"))
        
        print(f"✅ Cached {len(commands)} verbose commands")
        
    finally:
        container.cleanup()
    
    return commands


@pytest.fixture(scope="session")
def cached_invalidation_commands(workspace_root, checkdef_demo_path, container_tool):
    """Run invalidation test commands and cache results."""
    container = CheckdefTestContainer(workspace_root, checkdef_demo_path, container_tool)
    container.start_container()
    
    commands = []
    
    try:
        print("🧪 Caching invalidation test commands...")
        
        # 1. Populate both caches
        print("📊 Populating foo cache...")
        commands.append(container.run_timed_command("nix run .#checklist-foo"))
        
        print("📊 Populating bar cache...")
        commands.append(container.run_timed_command("nix run .#checklist-bar"))
        
        # 2. Get baseline cached performance
        print("📊 Getting foo baseline...")
        commands.append(container.run_timed_command("nix run .#checklist-foo"))
        
        # 3. Modify bar module
        print("📊 Modifying bar module...")
        commands.append(container.run_timed_command("echo '# timestamp change' >> src/bar/__init__.py"))
        
        # 4. Test foo after bar change (should still be fast)
        print("📊 Testing foo after bar change...")
        commands.append(container.run_timed_command("nix run .#checklist-foo"))
        
        # 5. Test bar after change (should rebuild)
        print("📊 Testing bar after change...")
        commands.append(container.run_timed_command("nix run .#checklist-bar"))
        
        print(f"✅ Cached {len(commands)} invalidation commands")
        
    finally:
        container.cleanup()
    
    return commands


@pytest.fixture(scope="session")
def cached_timing_commands(workspace_root, checkdef_demo_path, container_tool):
    """Run commands to test timing display behavior."""
    container = CheckdefTestContainer(workspace_root, checkdef_demo_path, container_tool)
    container.start_container()
    
    commands = []
    
    try:
        print("🧪 Caching timing test commands...")
        
        # 1. Run script-based check (ruff linters) - should show single timing
        print("📊 Running script-based linters...")
        commands.append(container.run_timed_command("nix run .#checklist-linters"))
        
        # 2. Run derivation-based check (first time) - should take longer
        print("📊 Running derivation-based foo (initial)...")
        commands.append(container.run_timed_command("nix run .#checklist-foo"))
        
        # 3. Run derivation-based check (cached) - should be fast but show both timings
        print("📊 Running derivation-based foo (cached)...")
        commands.append(container.run_timed_command("nix run .#checklist-foo"))
        
        # 4. Run mixed check (script + derivation)
        print("📊 Running mixed checklist-all...")
        commands.append(container.run_timed_command("nix run .#checklist-all"))
        
        print(f"✅ Cached {len(commands)} timing commands")
        
    finally:
        container.cleanup()
    
    return commands


class TestCacheBehavior:
    """Test checkdef's selective caching behavior."""
    
    @pytest.mark.integration
    @pytest.mark.container
    def test_selective_caching_performance(self, cached_performance_commands):
        """Test that selective caching provides expected performance improvements."""
        
        # Unpack cached command results
        uncached_foo, first_bar, partially_cached_foo, fully_cached_foo, cached_bar = cached_performance_commands
        
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
        
        # Unpack cached command results
        initial_foo, initial_bar, baseline_foo, change_bar, post_change_foo, post_change_bar = cached_invalidation_commands
        
        # Verify all commands succeeded
        assert initial_foo.succeeded, f"Initial foo run failed: {initial_foo.output}"
        assert initial_bar.succeeded, f"Initial bar run failed: {initial_bar.output}"
        assert baseline_foo.succeeded, f"Baseline foo run failed: {baseline_foo.output}"
        assert change_bar.succeeded, f"Bar change failed: {change_bar.output}"
        assert post_change_foo.succeeded, f"Post-change foo run failed: {post_change_foo.output}"
        assert post_change_bar.succeeded, f"Post-change bar run failed: {post_change_bar.output}"
        
        print(f"📈 Selective invalidation results:")
        print(f"   Foo baseline: {baseline_foo.duration:.3f}s")
        print(f"   Foo after bar change: {post_change_foo.duration:.3f}s") 
        print(f"   Bar after change: {post_change_bar.duration:.3f}s")
        
        # Foo should remain fast (cache not invalidated)
        assert post_change_foo.duration < baseline_foo.duration * 1.3, \
            f"Foo cache was invalidated by bar change: {post_change_foo.duration:.3f}s vs {baseline_foo.duration:.3f}s"
            
        # Bar should be slower (cache invalidated)
        assert post_change_bar.duration > baseline_foo.duration * 0.8, \
            f"Bar cache was not invalidated by change: {post_change_bar.duration:.3f}s"
            
        print("✅ Selective invalidation validation passed!")
        
    @pytest.mark.integration
    @pytest.mark.container
    def test_verbose_logging_behavior(self, cached_verbose_commands):
        """Test that verbose flag controls logging output."""
        
        # Unpack cached command results
        foo_normal, foo_verbose, bar_normal, bar_verbose = cached_verbose_commands
        
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
        
        # Unpack cached command results
        foo_normal, foo_verbose, bar_normal, bar_verbose = cached_verbose_commands
        
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
    def test_derivation_timing_display(self, cached_timing_commands):
        """Test that derivation-based checks show both original and reference timing when cached."""
        
        # Unpack cached command results
        script_check, initial_derivation, cached_derivation, mixed_check = cached_timing_commands
        
        # Verify all commands succeeded
        assert script_check.succeeded, f"Script check failed: {script_check.output}"
        assert initial_derivation.succeeded, f"Initial derivation check failed: {initial_derivation.output}"
        assert cached_derivation.succeeded, f"Cached derivation check failed: {cached_derivation.output}"
        assert mixed_check.succeeded, f"Mixed check failed: {mixed_check.output}"
        
        print("🧪 Testing derivation timing display...")
        
        # Cached derivation runs should show both original and reference timing
        # Look for pattern like "(original: 10.017s reference: 0.067s)"
        timing_pattern = r'\(original:\s*\d+\.\d+s\s+reference:\s*\d+\.\d+s\)'
        
        assert cached_derivation.contains_log_pattern(timing_pattern), \
            f"Cached derivation should show original+reference timing but output: {cached_derivation.output[:1000]}"
        
        # The mixed check should also show the dual timing for derivation parts
        assert mixed_check.contains_log_pattern(timing_pattern), \
            f"Mixed check should show original+reference timing for derivation parts but output: {mixed_check.output[:1000]}"
        
        print("✅ Derivation timing display validation passed!")
        
    @pytest.mark.integration
    @pytest.mark.container
    def test_script_timing_display(self, cached_timing_commands):
        """Test that script-based checks show single timing value."""
        
        # Unpack cached command results  
        script_check, initial_derivation, cached_derivation, mixed_check = cached_timing_commands
        
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