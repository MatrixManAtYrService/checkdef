# Checkdef

Checkdef is an experimental dev environment consistency check framework.
Its goal is to waste less time checking things that haven't changed since the last time you checked them.

Nix projects often have flake outputs which represent the project's runnable artifact.
This lets people build your software without thinking at all about which tools (beside nix) are needed to do so:

```
❯ nix build github:user/app#.bar  # "bar" an output of this repo's flake
❯ ./result/bin/bar                # nix built it, now we can run it
```

Checkdef explores using flake outputs to publish the output of tests, linters, and other such tools that might otherwise require a bit of setup on the user's part.
If you want to see which tests are passing and which tests are failing, checkdef helps make this possible:

```
❯ nix run github:fooUser/barApp#checklist
[linters]
✅ ruff - PASSED (0.293s)
✅ pyright - PASSED (3.803s)
[tests]
✅ pytest (tests) - PASSED (8.993s)
✅ pytest (integration_tests) - PASSED (68.004s)
================================================
🎉 All checks passed!
```

In a sense, this makes more of the dev environment "part of the app", which eliminates several headaches:

- tests that pass on this machine but not that one
- CI related problems that can't be tested locally
- static analysis tools that disagree between devs or between devs and CI

Also, nix understands environments as functions--so it knows what the inputs are.
This means that it can be configured to run the tests **only if their inputs have changed**.

For instance, rerunning the above command might show you this (notice the `original`/`reference` timing):

```
❯ nix run github:fooUser/barApp#checklist
[linters]
✅ ruff - PASSED (0.293s)
✅ pyright - PASSED (3.803s)
[tests]
✅ pytest (tests) - PASSED (original: 8.993s reference: 0.064s)
✅ pytest (integration_tests) - PASSED (original: 68.004s reference:0.138s)
================================================
🎉 All checks passed!
```
The first run cached your test results in `/nix/store`, and since nothing changed, the second run skipped the tests and just gave you the prior results.
For more on this, and an idea of how to use it, see [checkdef-demo](https://github.com/MatrixManAtYrService/checkdef-demo).

Used properly, I think it could potentially save a lot of time and money.

# Status

It works, but there's a lot of ugliness here.
Most eggregious are the large chunks of vibe-coded and poorly tested bash embedded in nix expressions in [nix/lib](nix/lib).

My intention is to use it for a few projects and make sure that the overall structure works well, and then replace as much of that bash as possible with a sort of check-running multitool which will be bette tested and have somewhat uniform usage across checks.

# Usage

Better docs will become available when I think it's ready for public consumption.
Here's the gist:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    checkdef.url = "github:MatrixManAtYrService/checkdef";
  };

  outputs = { self, nixpkgs, checkdef, ... }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    in
    {
      packages = forAllSystems
        (system:
          let
            # indicate your code
            src = ./.;

            # call checkdef.lib with nixpkgs to get the set of checks
            checks = checkdef.lib nixpkgs.legacyPackages.${system};

            # define a check runner for this set of checks
            linters = checks.runner {
              inherit src;
              name = "linters";
              includePatterns = [ "src/**" "test/**" ];
              scriptChecks = {
                ruffCheck = checks.ruff-check { inherit src; };
                ruffFormat = checks.pyright { inherit src; };
              };
            };

            pythonEnv = ...; # assemble your language-specific dependencies here
            # this example uses `pytest-cached` which needs a python environment
            # you can add check definitions for any language ecosystem

            # define separate checks for different things you care about
            unit-tests = checks.pytest-cached {
              inherit src pythonEnv;
              name = "unit-tests";
              description = "Unit tests";
              includePatterns = [
                "src/**"
                "tests/**"
              ];
              tests = [ "tests" ];
            };

            integration-tests = checks.pytest-cached {
              inherit src pythonEnv;
              name = "integration-tests";
              description = "Integration tests";
              includePatterns = [
                "src/**"
                "integration_tests/**"
              ];
              tests = [ "integration_tests" ];
            };

            # assemble them in a runner
            tests = checks.runner {
              name = "tests";
              derivationChecks = {
                inherit unit-tests integration-tests;
              };
            };

          in
          {
            # add the check runners as flake outputs
            inherit linters tests;
          });
    };
}
```

If you feel like that's a bit too much clutter for your flake, consider exploring the `/nix` folder in [htutil](https://github.com/MatrixManAtYrService/htutil) which uses checkdef and [blueprint](https://github.com/numtide/blueprint) together for a nicely organized repo.
