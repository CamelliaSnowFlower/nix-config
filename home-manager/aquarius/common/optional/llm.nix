{pkgs, ... }: {

    home.packages = with pkgs.unstable; [
      ollama
      # llama-cpp
    ];
  }

