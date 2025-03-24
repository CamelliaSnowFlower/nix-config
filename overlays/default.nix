# This file defines overlays
{inputs, ...}: {
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev: import ../pkgs final.pkgs;

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://nixos.wiki/wiki/Overlays
  modifications = final: prev: let
        version = "1.4.2";
        hash = "sha256-xe0qlbtt06CUK8bXyaGDtCcHOXpSnkbuvcxaDJjeS/c=";
        npmHash = "sha256-/+NhlQydGS6+2jEjpbwycwKplVo/++wcdPiBNY3R3FI=";
        cargoHash = "sha256-VwzGbm34t7mg9ndmTkht6Ho32NQ+6uxuPTKi3+VrhYo=";
      in {
        gale = prev.gale.overrideAttrs (new: old: {
          src = prev.fetchFromGitHub {
            inherit version hash;
            owner = "Kesomannen";
            repo = "gale";
            rev = "1.4.2";
          };
          npmDeps = prev.fetchNpmDeps {
            hash = npmHash;
            name = "${new.pname}-${new.version}-npm-deps";
            inherit (new) src;
          };
          cargoDeps = prev.rustPlatform.fetchCargoVendor {
            inherit
              (new)
              pname
              version
              src
              cargoRoot
              ;
            hash = cargoHash;
          };
        });
      };

  # When applied, the unstable nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.unstable'
  unstable-packages = final: _prev: {
    unstable = import inputs.nixpkgs-unstable {
      system = final.system;
      config.allowUnfree = true;
    };
  };
}
