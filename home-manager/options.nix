{lib, ...}: {
  options.profiles = {
    photography.enable = lib.mkEnableOption "photography and image-editing tools";
    coding.enable = lib.mkEnableOption "git, neovim, and other dev tooling";
    sysadmin.enable = lib.mkEnableOption "nix workflow scripts and system CLI tools";
    desktop.enable = lib.mkEnableOption "desktop-environment GUI packages";
    unstable.enable = lib.mkEnableOption "packages pulled from nixpkgs-unstable";
  };
}
