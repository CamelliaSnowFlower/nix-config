# The profiles.* options these modules read are declared in ../options.nix,
# which ../common imports. Import both ../common and ../optional.
{...}: {
  imports = [
    ./desktop.nix
    ./unstable.nix
  ];
}
