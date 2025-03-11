{
  description = "iob-ibex environment with ibex-demo-system dependencies";

  inputs = {
    ibex-demo-system.url = "github:lowRISC/ibex-demo-system";
    nixpkgs.follows = "ibex-demo-system/nixpkgs";
    flake-utils.follows = "ibex-demo-system/flake-utils";
    poetry2nix.follows = "ibex-demo-system/poetry2nix";
  };

  outputs = { self, nixpkgs, flake-utils, ibex-demo-system, ... }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs { inherit system; };
      ibexEnv = ibex-demo-system.outputs.devShells.${system}.default;
    in {
      devShells.default = pkgs.mkShell {
        name = "iob-ibex-env";
        buildInputs = ibexEnv.buildInputs;
        nativeBuildInputs = ibexEnv.nativeBuildInputs;
        shellHook = ibexEnv.shellHook;
      };
    });
}
