{pkgs, ... }: {

    home.packages = with pkgs.unstable; [
      lamma-cpp
    ];
  }

