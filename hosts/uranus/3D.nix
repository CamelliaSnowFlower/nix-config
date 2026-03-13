{pkgs, ... }: {


  environment.systemPackages = with pkgs; [
    freecad
    blender-hip
    orca-slicer
    # for orca-slicer scripts 
    pypy3
  ];
}
