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
  };
  # steam. mods, and minecraft tools
  environment.systemPackages = with pkgs; [
    protonup-ng
    mangohud
    prismlauncher
    # for prismlauncher 
    zulu17 
    r2modman
  ];

  environment.sessionVariables = {
    STEAM_EXTRA_COMPAT_TOOLS_PATHS = "\${HOME}/.steam/root/compatibilitytools.d";
  };
}
