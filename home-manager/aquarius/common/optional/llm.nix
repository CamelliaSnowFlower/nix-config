{pkgs, ... }: {

    home.packages = with pkgs.ustable; [
      ollma
    ];
  }

