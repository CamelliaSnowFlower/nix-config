{
  lib,
  appimageTools,
  fetchzip,
}: let
  pname = "deepnest";
  version = "1.0.5";

  # Deepnest isn't in nixpkgs, and deepnest.io only ships a zip
  # containing the AppImage (plus some sample files we don't need), so
  # this fetches the zip and points appimageTools at the AppImage
  # inside it.
  src = fetchzip {
    url = "https://deepnest.io/Deepnest-${version}-linux.zip";
    # Placeholder. Nix will refuse to build and print the real hash
    # the first time - swap it in when that happens.
    hash = lib.fakeHash;
    stripRoot = true;
  };

  appimage = "${src}/Deepnest-${version}-x86_64.AppImage";

  appimageContents = appimageTools.extractType2 {
    inherit pname version;
    src = appimage;
  };
in
  appimageTools.wrapType2 {
    inherit pname version;
    src = appimage;

    extraInstallCommands = ''
      install -Dm444 ${appimageContents}/deepnest.desktop -t $out/share/applications
      substituteInPlace $out/share/applications/deepnest.desktop \
        --replace-fail 'Exec=AppRun' 'Exec=deepnest'
      if [ -d ${appimageContents}/usr/share/icons ]; then
        cp -r ${appimageContents}/usr/share/icons $out/share/
      fi
    '';

    meta = {
      description = "Nesting software for laser/plasma/CNC cutting";
      homepage = "https://deepnest.io/";
      license = lib.licenses.mit;
      platforms = ["x86_64-linux"];
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
      mainProgram = "deepnest";
    };
  }
