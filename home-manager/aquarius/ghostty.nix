{
  lib,
  pkgs,
  ...
}: {
  programs.ghostty = {
    enable = true;
    package = pkgs.ghostty;

    enableBashIntegration = true;

    # Stylix's ghostty target writes font-family/font-size from
    # stylix.fonts.monospace at mkDefault priority, so a plain
    # assignment here would already win - mkForce just makes that
    # explicit and future-proof against priority changes upstream.
    settings = {
      font-family = lib.mkForce "Monocraft";
      font-size = lib.mkForce 14;

      # Torchlight cursor - warm and solid, like an ember, with the
      # character underneath dark enough to still read clearly.
      cursor-style = "block";
      cursor-style-blink = true;
      cursor-color = "#ff9e3f";
      cursor-text = "#1a1006";

      # Depth and coziness - a bit see-through and softened, like a
      # lit-up room in a dark cave rather than a flat block of color.
      background-opacity = 0.92;
      background-blur-radius = 20;

      # Breathing room around the text.
      window-padding-x = 12;
      window-padding-y = 12;

      # Nudge yellow/red palette slots warmer (amber/ember) without
      # overriding the rest of Stylix's base16 scheme.
      palette = [
        "3=#e8a33d"
        "1=#c25c3f"
      ];

      # Keep things legible even with a moody/dim theme.
      minimum-contrast = 1.1;
      adjust-cell-height = "5%";
    };
  };

  # Only pull Monocraft in for Ghostty - it isn't wired into
  # stylix.fonts, so it needs to be installed separately.
  home.packages = [pkgs.monocraft];
}
