{
  description = "raspberry pi image for heating device";
  inputs.template.url = "path:../template";

  outputs = { self, template }:
    let settings = builtins.fromJSON (builtins.readFile ./settings.json);
    in
    {
      nixosConfigurations.rpi-ebus =
        template.makePi ({ hostname = "rpi-ebus"; } // settings) [
          ({ config, pkgs, lib, modulesPath, ... }: {
            nixpkgs.config.packageOverrides = pkgs: {
              # grafana: somehow CGO is disabled on aarch64 implicitly. But required for sqlite3 in grafana
              grafana = pkgs.grafana.overrideAttrs (old: { CGO_ENABLED = 1; });
              # ebus: our custom ebus parser
              ebus = (pkgs.callPackage ./ebus-rust { });
            };

            services.influxdb.enable = true;
            services.influxdb.dataDir = "/data/influxdb";
            services.influxdb.enableCollectd = false;
            systemd.services.influxdb-init = {
              requires = [ "influxdb.service" ];
              after = [ "influxdb.service" ];
              wantedBy = [ "default.target" ];
              path = [ pkgs.influxdb ];
              script = ''
                influx -execute 'CREATE DATABASE "ebus"'
              '';
            };
            services.grafana = {
              enable = true;
              auth = {
                anonymous = {
                  enable = true;
                  org_role = "Admin";
                };
              };
              provision = {
                enable = true;
                datasources = [{
                  name = "InfluxDB";
                  type = "influxdb";
                  url = "http://localhost:8086";
                  database = "ebus";
                }];
              };
            };
            networking.firewall.allowedTCPPorts = [ 80 ];
            services.nginx = {
              enable = true;
              virtualHosts."rpi-ebus" = {
                basicAuth = { "${settings.username}" = settings.password; };
                locations."/" = {
                  proxyPass = "http://localhost:3000";
                  extraConfig = ''
                    proxy_set_header Authorization "";
                  '';
                };
              };
            };
            systemd.services.ebus = {
              description = "ebus protocol parser and influxdb inserter";
              wantedBy = [ "multi-user.target" ];
              after = [ "networking.target" "influxdb.service" ];
              script = ''
                ${pkgs.coreutils}/bin/stty 9600 < /dev/ttyUSB0
                RUST_LOG=info ${pkgs.ebus}/bin/ebus --enhanced influxdb < /dev/ttyUSB0
              '';
              serviceConfig = { User = settings.username; };
            };
          })
        ];
    };
}
