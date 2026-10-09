{ pkgs, config, inputs, ... }:
let unstable-pkgs = import inputs.nixpkgs-unstable { system = pkgs.stdenv.system; };
in {
  packages = [
    unstable-pkgs.zig_0_16
    unstable-pkgs.beam29Packages.elixir_1_20
  ];

  enterTest = ''
    mix deps.get
    mix test
  '';
}
