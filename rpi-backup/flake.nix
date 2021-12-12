{
  description = "raspberry pi image for backup";
  inputs.template.url = "path:../template";
  inputs.flake-utils = {
    url = "github:numtide/flake-utils";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, template, flake-utils }:
    let settings = builtins.fromJSON (builtins.readFile ./settings.json);
    in
    {
      # System configuration of the backup raspberry pi
      nixosConfigurations.rpi-backup =
        template.makePi ({ hostname = "rpi-backup"; } // settings) [
          ({ config, pkgs, lib, modulesPath, ... }: {
            nixpkgs.config.packageOverrides = pkgs: {
              zfs = pkgs.zfs.override {
                samba = "";
                enablePython = false;
                enableMail = false;
              };
            };
            services.udev.extraRules = ''
              ACTION=="add|change", KERNEL=="sd[a-z]*[0-9]*", ATTR{../queue/scheduler}="none"
            '';
            boot.supportedFilesystems = lib.mkForce [ "zfs" ];
            services.zfs.autoScrub = {
              enable = true;
              pools = [ "tank" ];
              interval = "Sun, 02:00";
            };
            users.users.root = {
              openssh.authorizedKeys.keys = settings.rootAuthorizedKeys;
            };
            environment.systemPackages = [
              (pkgs.runCommand "zfs-replicate-shell" { } ''
                mkdir -p $out/bin
                cp ${./zfs-replicate-shell} $out/bin/zfs-replicate-shell
              '')
            ];
          })
        ];
    } // flake-utils.lib.eachDefaultSystem (system:
      # Developer shell: $ nix develop path:.
      # used to deploy to the debian system
      {
        devShell =
          let
            pkgs = nixpkgs.legacyPackages.${system};
            sourceSendService = pkgs.writeText "zfs-replicate-snapshots.service" ''
              [Unit]
              Description=Run zfs synchronization
              After=network.target

              [Install]
              WantedBy=multi-user.target

              [Service]
              ExecStart=/usr/local/sbin/source-send.sh
            '';
            sourceSendScript = pkgs.writeText "source-send.sh" ''
              #!/usr/bin/env bash
              # To mark an fs for transfer do:
              #   $ zfs set localnet:strip=ssd_tank/ ssd_tank/machines/hostname
              #   $ zfs set localnet:add=backup/ ssd_tank/machines/hostname
              # Both options need to be set. Set both to "/" for no change.
              ZRS=/usr/local/sbin/zfs-replicate-shell
              while true; do
                for fs in $(zfs get -H -o name -t filesystem name); do
                  fs_strip=$(zfs get -H -o value -t filesystem localnet:strip "$fs")
                  fs_add=$(zfs get -H -o value -t filesystem localnet:add "$fs")
                  if [ "$fs_strip" == "-" ]; then
                    fs_strip=""
                  fi
                  if [ "$fs_add" == "-" ]; then
                    fs_add=""
                  fi
                  if [ -z "$fs_strip" ] || [ -z "$fs_add" ]; then
                    continue # skip if neither strip or add has any value
                  fi
                  $ZRS -L5M -B32M -r -a "$fs_add" -s "$fs_strip" send "${settings.targetHost}" "$fs"
                done
                sleep 360
              done'';
          in
          pkgs.mkShell {
            buildInputs = [
              pkgs.fpm
              pkgs.nixpkgs-fmt
              (pkgs.writeScriptBin "deploy-debian-package" ''
                set -x -e
                tmp=$(mktemp -d /tmp/zfs-replicate.XXX)
                trap "rm -rf $tmp" EXIT

                cp ${./zfs-replicate-shell} "$tmp/zfs-replicate-shell"
                cp ${sourceSendScript} "$tmp/source-send.sh"
                chmod +x "$tmp/source-send.sh"
                cp ${sourceSendService} "$tmp/zfs-replicate-snapshots.service"

                fpm -s dir -t deb -n zfs-replicate -v 0.0.1-9999 -f -p "$tmp/zfs-replicate.deb" \
                    --deb-systemd "$tmp/zfs-replicate-snapshots.service" \
                    --prefix /usr/local/sbin \
                    -C "$tmp" source-send.sh zfs-replicate-shell

                scp "$tmp/zfs-replicate.deb" "${settings.sourceUser}@${settings.sourceHost}:/tmp/zfs-replicate.deb"
                ssh -t "${settings.sourceUser}@${settings.sourceHost}" "echo \"become root:\"; su -l -c \"dpkg -i /tmp/zfs-replicate.deb; rm /tmp/zfs-replicate.deb\""
              '')
            ];
          };
      }
    );
}
