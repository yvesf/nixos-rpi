{
  description = "raspberry pi image for scanner box";
  inputs.nixpkgs.url = "nixpkgs/nixos-21.05";

  outputs = { self, nixpkgs }:
    let
      settings = builtins.fromJSON (builtins.readFile ./settings.json);
      makePi = module:
        let
          sys = (nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ module ];
          });
        in sys // { sdImage = sys.config.system.build.sdImage; };
    in rec {
      nixosConfigurations.rpi-scanner = makePi ({ config, pkgs, lib, modulesPath, ... }:
         {
            imports = [
              (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
              (modulesPath + "/profiles/minimal.nix")
              (modulesPath + "/config/no-x-libs.nix")
              ./scanbd
            ];
            nixpkgs.crossSystem = lib.systems.examples.aarch64-multiplatform;

            nixpkgs.config.packageOverrides = pkgs: {
              # nix: do not depend on aws utils
              nix = pkgs.nix.override { withAWS = false; };

              ## cloud-utils: not depend on cdrkit that fails to compile and qemu that fetches all kind of python stuff
              cloud-utils = pkgs.cloud-utils.override {
                qemu-utils = null;
                cdrkit = null;
                wget = null;
                python3 = null;
              };

              # sane-backends: Disable some dependencies of sane that don't (cross) build for arm
              # sane-backends: disable more dependencies that are not required
              # sane-backends: workaround for cross-compilation
              sane-backends = (pkgs.sane-backends.override {
                libjpeg = pkgs.libjpeg_turbo; libpng = null; libtiff = null;
                curl = null; libxml2 = null; poppler = null;
                libv4l = null; avahi = null; libieee1284 = null;
                libgphoto2 = null; net-snmp = null; systemd = null;
              }).overrideAttrs (old: rec {
                BACKENDS = "genesys";

                postInstall = (lib.optionalString
                  (pkgs.stdenv.buildPlatform != pkgs.stdenv.targetPlatform) ''
                    # Workaround for cross-compilation issue: cannot execute sane-desc
                    mkdir -p tools/udev
                    touch tools/udev/libsane.rules
                    touch $out/etc/sane.d/net.conf
                  '') + old.postInstall;
              });

              # scanbd: resolve compilation issue
              # scanbd: install dbus policy file and rename user to scanner (dbus is not used)
              scanbd = (pkgs.scanbd.override {
                libjpeg = pkgs.libjpeg_turbo;
              }).overrideAttrs (old: rec {
                configureFlags = (lib.optionals
                  (pkgs.stdenv.hostPlatform != pkgs.stdenv.buildPlatform) [
                    # AC_FUNC_MALLOC is broken on cross builds.
                    "ac_cv_func_malloc_0_nonnull=yes"
                    "ac_cv_func_realloc_0_nonnull=yes"
                  ]) ++ old.configureFlags;
                postInstall = ''
                  install -Dm644 integration/scanbd_dbus.conf $out/share/dbus-1/system.d/scanbd.conf
                  substituteInPlace $out/share/dbus-1/system.d/scanbd.conf \
                    --replace 'user="saned"' 'user="scanner"'
                '';
              });

              # imagemagick: disable not required features/dependencies
              imagemagick = pkgs.imagemagick.override {
                bzip2 = null; zlib = null; libX11 = null; libXext = null; libXt = null;
                fontconfig = null; freetype = null; ghostscript = null; libjpeg = pkgs.libjpeg_turbo;
                djvulibre = null; lcms2 = null; openexr = null; libpng = null;
                librsvg = null; libtiff = null; libxml2 = null; openjpeg = null;
                libwebp = null; libheif = null;
              };
            };
            boot.supportedFilesystems = lib.mkForce [ "vfat" ];
            boot.initrd.supportedFilesystems = lib.mkForce [ ];
            boot.initrd.availableKernelModules = lib.mkOverride 0 [ ];
            boot.enableContainers = false;
            boot.growPartition = true;
            boot.kernelPackages = pkgs.linuxPackages_rpi4;
            boot.loader.raspberryPi = {
              enable = true;
              version = 4;
            };
            boot.loader.grub.enable = false;
            sdImage.compressImage = false;

            hardware.firmware = lib.mkForce [ pkgs.raspberrypiWirelessFirmware ];

            security.polkit.enable = false;
            services.udisks2.enable = false;
            xdg.sounds.enable = false;
            
            services.openssh.enable = true;

            systemd.enableEmergencyMode = false;
            powerManagement.enable = false;
            programs.command-not-found.enable = false;
            # supportedLocales is set by profiles/minimal
            i18n.defaultLocale = "en_US.UTF-8"; 

            networking.useDHCP = true;
            networking.wireless.enable = true;
            networking.wireless.interfaces =
              [ "wlan0" ]; # workaround for #101963
            networking.wireless.networks = settings.wireless;
            networking.firewall.allowedTCPPorts = [ 22 80 ];

            # disable packages to reduce size
            environment.defaultPackages = [ ];
            environment.systemPackages = [ pkgs.vim ];
            
            # Project specific configuration:
            services.lighttpd = {
              enable = true;
              document-root = "/data";
              extraConfig = ''
                dir-listing.activate = "enable"
              '';
            };

            networking.hostName = "rpi-scanner";

            fileSystems."/data" = {
              device = "/dev/disk/by-label/data";
              fsType = "ext4";
            };

            nix.trustedUsers = [ settings.username ];
            users.mutableUsers = false;
            users.users."${settings.username}" = {
              password = settings.password;
              isNormalUser = true;
              extraGroups = [ "wheel" ];
              uid = 1000;
              openssh.authorizedKeys.keys = settings.authorizedKeys;
            };
            security.sudo.wheelNeedsPassword = false;
            
            services.scanbd.enable = true;
            services.udev.extraRules = ''
              SUBSYSTEM=="usb", ATTR{idVendor}=="04a9", ATTR{idProduct}=="1909", MODE="666"
            '';
          });
    };
}
