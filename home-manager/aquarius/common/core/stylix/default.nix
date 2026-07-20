
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

    # gtksourceview's stylix target forces a local rebuild of anything
    # linking it - including inkscape - instead of using the cached
    # binary from Hydra. Not worth the multi-hour Inkscape compile for
    # a themed XML editor pane.
    targets.gtksourceview.enable = false;

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
