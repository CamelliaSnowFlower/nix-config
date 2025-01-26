{pkgs, ... }: {

    home.packages = with pkgs.unstable; [
      ollma
    ];
  }

