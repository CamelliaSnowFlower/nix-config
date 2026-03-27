
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: {
  imports = [
    inputs.stylix.homeManagerModules.default
  ];

  stylix = [
    enable = true;
    base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-hard.yaml";

  ];
}
