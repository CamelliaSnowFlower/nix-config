{
  config,
  lib,
  ...
}: {
  programs.ghostty = {
    enable = true;
    settings = {
      theme = "light:GruvboxLight,dark:GruvboxDark";
    };
  };
}
