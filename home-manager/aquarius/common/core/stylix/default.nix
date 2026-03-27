
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

  stylix = {
    enable = true;
    image = ./TADC.jpg;
    polarity ="dark";
    targets.firefox.enable = true;
};
}
