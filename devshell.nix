# devshell.nix - tools for working on this repo. Enter with `nix develop`
# (or automatically via direnv and .envrc). Wired up in flake.nix.
{pkgs}:
pkgs.mkShell {
  packages = with pkgs; [
    # Nix tooling
    nixd # language server (completion, option docs)
    alejandra # formatter, same one `nix fmt` uses
    statix # linter for common Nix anti-patterns
    deadnix # finds unused bindings
    nvd # diffs two system builds

    # What scripts/check.sh needs for the sticker and shell tests
    shellcheck
    imagemagick
    (python3.withPackages (ps: [ps.numpy ps.pillow]))
  ];
}
