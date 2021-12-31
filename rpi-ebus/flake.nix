{
  description = "raspberry pi image for heating device";
  inputs.template.url = "path:../template";
  inputs.ebus.url = "github:yvesf/ebus";
  inputs.ebus.inputs.nixpkgs.follows = "template/nixpkgs";

  outputs = { self, template, ebus }:
    let settings = builtins.fromJSON (builtins.readFile ./settings.json);
    in
    {
      nixosConfigurations.rpi-ebus =
        template.makePi ({ hostname = "rpi-ebus"; } // settings) [
          ({ config, pkgs, lib, modulesPath, ... }: {
            nixpkgs.config.packageOverrides = pkgs: {
              # grafana: somehow CGO is disabled on aarch64 implicitly. But required for sqlite3 in grafana
              grafana = pkgs.grafana.overrideAttrs (old: { CGO_ENABLED = 1; });
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

            services.ebus-rust.enable = true;
            services.ebus-rust.user = settings.username;
            services.ebus-rust.device = "/dev/ttyUSB0";
          })

					template.nixosModules.networkingWifi
					ebus.nixosModules.ebus-rust
        ];
    };
}
