{
  description = "csoul — a colorscheme picker UI study for Neovim";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];

      eachSystem = f:
        nixpkgs.lib.genAttrs systems
          (system: f system nixpkgs.legacyPackages.${system});
    in {
      devShells = eachSystem (_system: pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.python3 pkgs.neovim pkgs.git ];
        };
      });

      packages = eachSystem (_system: pkgs: {
        default = pkgs.writeShellApplication {
          name = "csoul-preview";
          runtimeInputs = [ pkgs.python3 pkgs.neovim ];
          text = ''
            exec python3 ${./preview.py} "$@"
          '';
        };

        nvim-plugin = pkgs.vimUtils.buildVimPlugin {
          pname = "csoul.nvim";
          version = "0.1.0";
          src = nixpkgs.lib.fileset.toSource {
            root = ./.;
            fileset = nixpkgs.lib.fileset.unions [ ./lua ./plugin ];
          };
        };
      });

      apps = eachSystem (system: _pkgs: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/csoul-preview";
        };
      });
    };
}
