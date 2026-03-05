{config, ...}: {
# import this into nvidia.nix and you should be good
  hardware.nvdia.prime = {
    offload.enable = true;
    offload.enableOffloadCmd = true;

    # run the following to find the pci ports for the graphics cards
    # nix shell nixpkgs#pciutils -c lspci | grep VGA
    intelBusId = "";
    nvidiaBusId = "";
  };


}
