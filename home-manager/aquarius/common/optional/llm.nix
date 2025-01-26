{pkgs, ... }: {

    home.packages = with pkgs.unstable; [
      ollama
    ];
  }

