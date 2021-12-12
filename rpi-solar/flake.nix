{
  description = "raspberry pi image for solar inverter";
  inputs.template.url = "path:../template";

  outputs = { self, template }:
    let settings = builtins.fromJSON (builtins.readFile ./settings.json);
    in {
      nixosConfigurations.rpi-solar =
        template.makePi ({ hostname = "rpi-solar"; } // settings) [
          ({ config, pkgs, lib, modulesPath, ... }: {
            nixpkgs.config.packageOverrides = pkgs: {
              # grafana: somehow CGO is disabled on aarch64 implicitly. But required for sqlite3 in grafana
              grafana = pkgs.grafana.overrideAttrs (old: { CGO_ENABLED = 1; });
            };

            services.influxdb.enable = true;
            services.influxdb.enableCollectd = false;
            systemd.services.influxdb-init = {
              requires = [ "influxdb.service" ];
              after = [ "influxdb.service" ];
              wantedBy = [ "default.target" ];
              path = [ pkgs.influxdb ];
              script = ''
                influx -execute 'CREATE DATABASE "solardaten"'
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
                  database = "solardaten";
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
            # run dnsmasq to give addresses to the inverter
            services.dnsmasq = {
              enable = true;
              extraConfig = ''
                interface = eth0;
				dhcp-range=eth0,192.168.1.100,192.168.1.199,15m
				no-resolv
              '';
            };
            services.i2pd = {
              enable = true;
              inTunnels = {
                ssh = {
                  enable = true;
                  keys = "ssh.keys";
                  inPort = 22;
                  address = "::1";
                  destination = "::1";
                  port = 22;
                  inbound.length = 0;
                  outbound.length = 0;
                };
                http = {
                  enable = true;
                  keys = "http.keys";
                  inPort = 80;
                  address = "::1";
                  destination = "::1";
                  port = 80;
                  inbound.length = 0;
                  outbound.length = 0;
                };
              };
            };
          })
        ];
    };
}
