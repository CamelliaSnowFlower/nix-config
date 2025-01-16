{config, lib, ... }:
{
 services.spotifyd = {
  enable = true;
  settings = {
   global {
    username = "themexicanjames@gmail.com";
    password = "coksa5-zEvvaq-riqtev";

   };
  };
 };
 
}

# honestlty too much going on rn need to come back to this later when I have a more advance understanding of all the moving parts I would need to get this thing fully going need to go to this repo for inspo: https://github.com/EzequielRamis/dotfiles/blob/main/home/music.nix
