{ 
config,
pkgs,
...
}: {

  environment.systemPackages = with pkgs; [
        gnomeExtenstions.blur-my-shell
        ];
}

