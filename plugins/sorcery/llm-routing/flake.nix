{
  # Dev shell for the llm-routing scaffold. Pins the toolchain that
  # setup.sh, route.sh, and llm.sh need to run, so anyone on the team
  # gets the same Python/Bun/uv versions without per-machine drift.
  #
  # The flake intentionally does NOT package LiteLLM — that lives in a
  # repo-local .venv managed by uv (see setup.sh). Reason: LiteLLM
  # iterates fast and `uv pip install -U 'litellm[proxy]'` is the right
  # way to bump it; pinning it in nixpkgs fights the use case.
  #
  # Enter with:    nix develop
  # Run one-shot:  nix develop --command bash -c 'litellm --version'
  description = "llm-routing — LiteLLM proxy + Swival coding-agent dev shell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
    in {
      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.mkShell {
            packages = [
              pkgs.python313
              pkgs.uv
              pkgs.bun
              pkgs.curl
              pkgs.jq
              pkgs.ripgrep
            ];

            # Nix sets IN_NIX_SHELL automatically — scripts re-exec
            # themselves into `nix develop --command` when it's unset.
            # The greeting confirms the shell is wired correctly on first
            # entry; silence it with `LLM_ROUTING_SILENT=1` if you want.
            shellHook = ''
              if [ -z "''${LLM_ROUTING_SILENT:-}" ]; then
                echo "llm-routing dev shell — python=$(python3 --version 2>&1 | awk '{print $2}') bun=$(bun --version) uv=$(uv --version | awk '{print $2}')"
              fi
            '';
          };
        });
    };
}
