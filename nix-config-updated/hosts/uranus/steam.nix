{
  config,
  pkgs,
  ...
}: {
  programs.gamemode.enable = true;
  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    extraPackages = with pkgs; [hidapi];
  };
  # steam. mods, and minecraft tools
  environment.systemPackages = with pkgs; [
    protonup-ng
    mangohud
    prismlauncher
    # for prismlauncher 
    zulu17
    zulu25 #vulkan minecraft
    r2modman
    extest
  ];

  environment.sessionVariables = {
    STEAM_EXTRA_COMPAT_TOOLS_PATHS = "\${HOME}/.steam/root/compatibilitytools.d";
  };
}
