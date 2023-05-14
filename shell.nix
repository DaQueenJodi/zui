let
  pkgs = import (fetchTarball {
    url = "https://github.com/nixos/nixpkgs/archive/115cf02e18713c21e3392a795689808df7798b36.tar.gz";
    sha256 = "1akr7f0wg6syr36m7in6jvz406cl5kb04zv2v9b9wkl1nvgrpkp6";
  }) {};
in
  pkgs.mkShell {
    nativeBuildInputs = with pkgs; [
      zig
    ];
  }
