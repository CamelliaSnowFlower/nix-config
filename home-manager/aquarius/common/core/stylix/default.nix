
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: {
  imports = [
    inputs.stylix.homeModules.default
  ];

  stylix = {
    enable = true;
    image = ./TADC.jpg;
    polarity ="dark";
    targets.firefox.firefoxGnomeTheme.enable = true;
};
}
