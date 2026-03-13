{pkgs, ... }: {


  environment.systemPackages = with pkgs; [
    freecad
    blender
    orca-slicer
    # for orca-slicer scripts 
    pypy3
  ];
}
