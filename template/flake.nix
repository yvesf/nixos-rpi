{
  inputs.nixpkgs.url =
    #    "/home/yvesf/vcs/nixpkgs";
    #    "github:nixpkgs/nixpkgs?rev=
    #"github:NixOS/nixpkgs/1fa5e13f30c60890b01475d7945a17ca5721a5f2";
    #    "github:NixOS/nixpkgs/1ab1b4561d28366e366167c658b7390a04ef867d";
    "nixpkgs/nixos-21.11";
  #    "github:NixOS/nixpkgs/5cb226a06c49f7a2d02863d0b5786a310599df6b";
  #"git+https://github.com/NixOS/nixpkgs?ref=nixpkgs-unstable&rev=5cb226a06c49f7a2d02863d0b5786a310599df6b";
  outputs = { self, nixpkgs }: {
    makePi = settings: modules:
      let
        sys = (nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
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

              nix.trustedUsers = [ settings.username ];
              users.mutableUsers = false;
              users.users."${settings.username}" = {
                password = settings.password;
                isNormalUser = true;
                extraGroups = [ "wheel" "dialout" ];
                uid = 1000;
                openssh.authorizedKeys.keys = settings.authorizedKeys;
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

              hardware.firmware =
                lib.mkForce [ pkgs.raspberrypiWirelessFirmware ];

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

              networking.useDHCP = true;
              networking.wireless.enable = true;
              # workaround for #101963:
              networking.wireless.interfaces = [ "wlan0" ];
              networking.wireless.networks = settings.wireless;
              networking.interfaces.eth0.ipv4.addresses = [{
                address =
                  "192.168.1.1"; # allows easy local access if wifi is broken
                prefixLength = 24;
              }];

              # disable packages to reduce size
              environment.defaultPackages = [ ];
              environment.systemPackages = [ pkgs.vim ];

              networking.hostName = settings.hostname;

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
