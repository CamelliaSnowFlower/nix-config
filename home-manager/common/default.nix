{...}: {
  imports = [
    ./git.nix
    ./scripts.nix
    ./packages-cli.nix
    ./packages-gui.nix
    ./packages-unstable-cli.nix
    ./packages-unstable-gui.nix
  ];
}
