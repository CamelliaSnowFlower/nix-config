{pkgs, config, lib, ... }:
{
 imports = [
  ./git.nix
  ./ghostty.nix
  ./scripts.nix
  ./nvim
 ];
}
