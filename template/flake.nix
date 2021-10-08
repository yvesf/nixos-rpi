{
  inputs.nixpkgs.url =
    "github:nixpkgs/nixpkgs?rev=1fa5e13f30c60890b01475d7945a17ca5721a5f2";
  outputs = { self, nixpkgs }: {
    makePi = settings: modules:
      let
        sys = (nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ({ config, pkgs, lib, modulesPath, ... }: {
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
              };

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
                "xhci_pci" "xhci_pci_renesas"  # required on  a 2gb model but not on a 4gb model
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
              networking.interfaces.eth0.ipv4.addresses = [ {
                address = "192.168.1.1"; # allows easy local access if wifi is broken
                prefixLength = 24;
              } ];

              # disable packages to reduce size
              environment.defaultPackages = [ ];
              environment.systemPackages = [ pkgs.vim ];

              networking.hostName = settings.hostname;

              fileSystems."/var" = {
                device = "/dev/disk/by-label/data";
                fsType = "ext4";
              };
            })
          ] ++ modules;
        });
      in sys // { sdImage = sys.config.system.build.sdImage; };
  };

}
