{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  nativeBuildInputs = with pkgs; [
    (pkgs.stdenv.mkDerivation rec {
      name = "zig";
      src = pkgs.fetchurl {
        url = "https://ziglang.org/builds/zig-linux-x86_64-0.11.0-dev.3379+629f0d23b.tar.xz";
        sha256 = "GqFt+xqcyJaNUv13X5ytYKB1f/wDEladtCR60G+sAHo=";
      };
      installPhase = ''
        mkdir -p $out/bin
        mv * $out/bin
      '';
    })
  ];
}
