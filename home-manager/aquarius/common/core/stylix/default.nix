
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
    fonts = {
      serif = {
      package = pkgs.dejavu_fonts;
      name = "DejaVu Serif";
      };

      sansSerif = {
      package = pkgs.dejavu_fonts;
      name = "DejaVu Sans";
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
