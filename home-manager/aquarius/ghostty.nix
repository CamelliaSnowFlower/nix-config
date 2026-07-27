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
      font-size = lib.mkForce 12;
    };
  };

  # Only pull Monocraft in for Ghostty - it isn't wired into
  # stylix.fonts, so it needs to be installed separately.
  home.packages = [pkgs.monocraft];
}
