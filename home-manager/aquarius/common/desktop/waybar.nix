{
  config,
  lib,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    gtkmm3
    font-awesome_5
  ];

  programs.waybar = {
    enable = true;
    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 30;
        output = "eDP-1";
        modules-right = [
          "clock"
          "battery"
        ];

        "clock" = {
          interval = 60;
          format = "{:%H:%M}";
          max-length = 25;
        };
        "battery" = {
          bat = "BAT0";
          interval = 60;
          states = {
            warning = 30;
            critical = 15;
          };
          format = "{capacity}% {icon}";
          format-icons = ["" "" "" "" ""];
          max-length = 25;
        };
      };
    };
  };
}
