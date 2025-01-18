{config, pkgs, ... }: {
  programs.kitty.enable = true;
  wayland.windowManager.hyperland = {
    enable = true;
    settings = {

    };
  };
}
