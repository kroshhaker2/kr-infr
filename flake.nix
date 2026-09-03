{
  description = "Kr production infrastructure";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (
          system: f nixpkgs.legacyPackages.${system}
        );
    in
    {
      devShells = forAllSystems (pkgs:
        let
          python = pkgs.python312;
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              python
              python.pkgs.pip
              python.pkgs.virtualenv

              git
              openssh
              jq
              yq
              sops
              age
            ];

            shellHook = ''
              export VIRTUAL_ENV="$PWD/.venv"
              export PATH="$VIRTUAL_ENV/bin:$PATH"

              if [ ! -d "$VIRTUAL_ENV" ]; then
                echo "Creating Python virtualenv..."
                ${python}/bin/python -m venv "$VIRTUAL_ENV"
              fi

              if [ ! -f "$VIRTUAL_ENV/.ansible-dev-tools-installed" ]; then
                echo "Installing ansible-dev-tools..."

                "$VIRTUAL_ENV/bin/python" -m pip install \
                  --upgrade pip

                "$VIRTUAL_ENV/bin/python" -m pip install \
                  ansible-dev-tools

                touch "$VIRTUAL_ENV/.ansible-dev-tools-installed"
              fi

              echo
              echo "Ansible development environment"
              echo "--------------------------------"
              echo "Python:  $(python --version)"
              echo "Ansible: $(ansible --version | head -n1)"
              echo
            '';
          };
        }
      );
    };
}