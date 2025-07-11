{ 
config,
pkgs,
...
}: {

  environment.systemPackages = with pkgs; [
gnome-shell-extension-blur-my-shell
        ];
}

