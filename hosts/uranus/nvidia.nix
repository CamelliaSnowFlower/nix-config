{config, ...}: {
  hardware = {
    graphics = {
      enable = true;
      enable32Bit = true;
    };
    nvidia = {
      modesetting.enable = true;
      nvidiaSettings = true;
      powerManagement.enable = false;
      powerManagement.finegrained = false;
      open = false;
      package = config.boot.kernelPackages.nvidiaPackages.beta;
    
      prime = {
      offload.enable = true;
      offload.enableOffloadCmd = true;

      # run the following to find the pci ports for the graphics cards
      # nix shell nixpkgs#pciutils -c lspci | grep VGA
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
      };
    };
  };
  services.xserver.videoDrivers = [
    "nvidia"
    "modesetting"
  ];
}
