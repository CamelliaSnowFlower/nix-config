{config, pkgs, lib, ... }: 

  let

  unstable = import inputs.nixpkgs-unstable {
    system = pkgs.system;
  };
 
  in

  {
    home.packages = with pkgs; [
      ollma
    ];
  }

