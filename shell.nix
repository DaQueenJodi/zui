{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  nativeBuildInputs = with pkgs; [
    (pkgs.stdenv.mkDerivation rec {
      name = "zig";
      src = pkgs.fetchurl {
        url = "https://ziglang.org/builds/zig-linux-x86_64-0.11.0-dev.3223+38b83d9d9.tar.xz";
        sha256 = "NXc3H90QLhYJfcPufyr/IoE2USETuLPPkyDgooGqGGg=";
      };
      installPhase = ''
        mkdir -p $out/bin
        mv * $out/bin
      '';
    })
    pkgconfig
    gdb
    SDL2
    SDL2_image
  ];
}
