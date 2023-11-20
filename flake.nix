{
  description = "api_guard flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # Used for shell.nix
    flake-compat = {
      url = github:edolstra/flake-compat;
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  } @ inputs: let
  in
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {inherit system; };
        pythonEnv = pkgs.python3.withPackages (ps: [
            ps.flask
            ps.python-dotenv
        ]);
      in rec {
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            bat
            gnused
            pythonEnv
            curl
          ];

          buildInputs = with pkgs; [
            # we need a version of bash capable of being interactive
            # as opposed to a bash just used for building this flake 
            # in non-interactive mode
            bashInteractive 
          ];

          shellHook = ''
            # once we set SHELL to point to the interactive bash, neovim will 
            # launch the correct $SHELL in its :terminal 
            export SHELL=${pkgs.bashInteractive}/bin/bash
            export FLASK_APP=api_guard:app
          '';
        };

        # For compatibility with older versions of the `nix` binary
        devShell = self.devShells.${system}.default;

        # packages
        packages.api_guard = pkgs.stdenv.mkDerivation rec {
          name = "api_guard";
          buildInputs = with pkgs; [
            pythonEnv
            busybox # grep, xargs
            bashInteractive 
          ];

          script = pkgs.writeShellScript "api_guard-run" ''
            #!/usr/bin/env bash
            
            # set a XDG_CONFIG_HOME if in docker
            export XDG_CONFIG_HOME=''${XDG_CONFIG_HOME:-/tmp}

            # Define the path to the .env file
            ENV_PATH="''${XDG_CONFIG_HOME}/api_guard/.env"

            # Load .env file from the specified path
            if [ -f "$ENV_PATH" ]; then
                export $(cat "$ENV_PATH" | ${pkgs.busybox}/bin/grep -v '^#' | ${pkgs.busybox}/bin/xargs)
            else
                # DOCKER 
                export $(cat "/tmp/.env" | ${pkgs.busybox}/bin/grep -v '^#' | ${pkgs.busybox}/bin/xargs)
            fi

            # Set default values if variables are not set in .env file
            PORT=''${PORT:-5000}
            LOGDIR=''${LOGDIR:-/tmp}

            # Start Gunicorn
            export PYTHONPATH=${pythonEnv}/${pythonEnv.sitePackages}
            ${pkgs.python3Packages.gunicorn}/bin/gunicorn -w 1 -b 0.0.0.0:$PORT --access-logfile $LOGDIR/access.log --error-logfile $LOGDIR/error.log api_guard:app
          '';

          src = ./.;

          installPhase = ''
            mkdir -p $out/bin
            cp -r . $out/bin/
            cp ${script} $out/bin/api_guard
          '';

        };
        defaultPackage = self.packages.${system}.api_guard;

        # Usage:
        #    nix build .#docker
        #    docker load < result
        #    docker run -p5000:5000 -v ${realpath ./rundir):/tmp api_guard:lastest
        packages.docker = pkgs.dockerTools.buildImage {
          name = "api_guard";       # give docker image a name
          tag = "latest";     # provide a tag
          created = "now";

          copyToRoot = pkgs.buildEnv {
            name = "image-root";
            paths = [ packages.api_guard pythonEnv pkgs.gnused pkgs.coreutils];
            pathsToLink = [ "/bin" "/tmp" ];
          };

          config = {
            Cmd = [ "${packages.api_guard}/bin/api_guard" ];
            WorkingDir = "/bin";
            Volumes = { 
                "/tmp" = { }; 
                };
            ExposedPorts = {
              "5000/tcp" = {};
            };
          };
        };


    });
}
