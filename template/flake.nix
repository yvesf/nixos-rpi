{
  inputs.nixpkgs.url = "nixpkgs/nixos-21.11";
  outputs = { self, nixpkgs }: {
  	nixosModules = {
  		# Networking option to use wifi and the "wireless" configuration from settings
  		networkingWifi = ({ config, pkgs, lib, modulesPath, ... }: {
				options = {};
				 config = {
           networking.useDHCP = true;
           networking.wireless.enable = true;
           # workaround for #101963:
           networking.wireless.interfaces = [ "wlan0" ];
           networking.wireless.networks = config.settings.wireless;
           networking.interfaces.eth0.ipv4.addresses = [{
             address =
               "192.168.1.1"; # allows easy local access if wifi is broken
             prefixLength = 24;
           }];

				};
  		});
  		networkingCableDHCP = ({ config, pkgs, lib, modulesPath, ... }: {
      	options = {};
      	 config = {
           networking.useDHCP = true;
           networking.wireless.enable = false;
           networking.interfaces.eth0.useDHCP = true;
      	};
      });
  	};
    makePi = settings: modules:
      let
        sys = (nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            # this module just sets the "settings"
            ({ lib, ...}:{
              options = {
                settings = lib.mkOption {
                	default = settings;
                	description = "json settings";
                	type = lib.types.attrs;
                };
              };
            })
            # base configuration
            ({ config, pkgs, lib, modulesPath, ... }: {
              disabledModules = [
                "services/databases/influxdb.nix" # replaced by ./modules/influxdb.nix
                "services/networking/i2pd.nix" # replaced by ./modules/i2pd.nix
              ];
              imports = [
                (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
                (modulesPath + "/profiles/minimal.nix")
                (modulesPath + "/config/no-x-libs.nix")
              ];
              nixpkgs.crossSystem = lib.systems.examples.aarch64-multiplatform;

              nixpkgs.config.packageOverrides = pkgs: {
                # nix: do not depend on aws utils
                nix = pkgs.nix.override { withAWS = false; };
                # cloud-utils: not depend on cdrkit that fails to compile and qemu that fetches all kind of python stuff
                cloud-utils = pkgs.cloud-utils.override {
                  qemu-utils = null;
                  cdrkit = null;
                  wget = null;
                  python3 = null;
                };
                # wpa_supplicant: disable pcsclite to disable dbus-python which fails to cross-compile
                wpa_supplicant = pkgs.wpa_supplicant.override {
                  withPcsclite = false;
                  pcsclite = null;
                };

                # xfsprogs: do not depend on icu4c
                xfsprogs = pkgs.xfsprogs.override { icu = null; };

                # vim: make it smaller
                vim = pkgs.vim_configurable.override {
                  features = "tiny";
                  guiSupport = false;
                  luaSupport = false;
                  pythonSupport = false;
                  rubySupport = false;
                  cscopeSupport = false;
                  netbeansSupport = false;
                  ximSupport = false;
                  ftNixSupport = false;
                };
              };

              # this goes a bit further than minimal.nix to reduce glibc size
              i18n.supportedLocales = [ "en_US.UTF-8/UTF-8" ];

              nix.trustedUsers = [ config.settings.username ];
              users.mutableUsers = false;
              users.users."${config.settings.username}" = {
                password = config.settings.password;
                isNormalUser = true;
                extraGroups = [ "wheel" "dialout" ];
                uid = 1000;
                openssh.authorizedKeys.keys = config.settings.authorizedKeys;
              };
              security.sudo.wheelNeedsPassword = false;

              boot.supportedFilesystems = lib.mkForce [ "vfat" ];
              boot.initrd.supportedFilesystems = lib.mkForce [ ];
              boot.initrd.availableKernelModules = lib.mkOverride 0 [
                "xhci_pci"
                "xhci_pci_renesas" # required on  a 2gb model but not on a 4gb model
              ];
              boot.enableContainers = false;
              boot.growPartition = true;
              boot.kernelPackages = pkgs.linuxPackages_rpi4;
              boot.loader.raspberryPi = {
                enable = true;
                version = 4;
              };
              boot.loader.grub.enable = false;
              sdImage.compressImage = false;

              security.polkit.enable = false;
              services.udisks2.enable = false;
              xdg.sounds.enable = false;

              services.openssh.enable = true;
              services.openssh.passwordAuthentication = false;
              networking.firewall.allowedTCPPorts = [ 22 ];

              systemd.enableEmergencyMode = false;
              powerManagement.enable = false;
              programs.command-not-found.enable = false;
              # supportedLocales is set by profiles/minimal
              i18n.defaultLocale = "en_US.UTF-8";

              hardware.firmware = lib.mkForce [ pkgs.raspberrypiWirelessFirmware ];

							networking.hostName = config.settings.hostname;

              # disable packages to reduce size
              environment.defaultPackages = [ ];
              environment.systemPackages = [ pkgs.vim ];

              nix.gc = {
                automatic = true;
                dates = "weekly";
                options = "--delete-older-than 60d";
              };

              fileSystems."/var" = {
                device = "/dev/disk/by-label/data";
                fsType = "ext4";
                options = [ "noatime" ];
              };
            })
            ./modules/influxdb.nix
            ./modules/i2pd.nix
          ] ++ modules;
        });
      in
      sys // { sdImage = sys.config.system.build.sdImage; };
  };

}
