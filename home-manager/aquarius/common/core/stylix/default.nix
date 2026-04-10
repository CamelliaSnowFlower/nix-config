
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
    autoEnable = true;
    image = ./TADC.jpg;
    polarity ="dark";
    fonts = {
      serif = {
      package = pkgs.scientifica;
      name = "Scientifica Serif";
      };

      sansSerif = {
      package = pkgs.scientifica;
      name = "Scientifica Sans";
      };

      monospace = {
      package = pkgs.dejavu_fonts;
      name = "DejaVu Sans Mono";
      };
      
      emoji = {
      package = pkgs.noto-fonts-color-emoji;
      name = "Noto Color Emoji";
      };
    };
};
}
