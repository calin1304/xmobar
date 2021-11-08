{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = [
    pkgs.alsaLib
    pkgs.pkgconfig
    pkgs.wirelesstools
    pkgs.xorg.libX11
    pkgs.xorg.libXext
    pkgs.xorg.libXft
    pkgs.xorg.libXpm
    pkgs.xorg.libXrandr
    pkgs.xorg.libXScrnSaver
    pkgs.zlib
    pkgs.hello
    pkgs.gmp
    pkgs.mpfr

    # keep this line if you use bash
    pkgs.bashInteractive
  ];
}
