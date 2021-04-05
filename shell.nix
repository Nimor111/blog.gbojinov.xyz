{pkgs ? import <nixpkgs> {}}:

pkgs.mkShell {
  buildInputs = [
    pkgs.hugo
    pkgs.ammonite
  ];
}
