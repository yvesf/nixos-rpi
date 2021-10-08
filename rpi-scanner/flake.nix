{
  description = "raspberry pi image for scanner box";
  inputs.template.url = "path:../template";

  outputs = { self, template }:
    let settings = builtins.fromJSON (builtins.readFile ./settings.json);
    in {
      nixosConfigurations.rpi-scanner =
        template.makePi ({ hostname = "rpi-scanner"; } // settings) [
          ({ config, pkgs, lib, modulesPath, ... }: {
            nixpkgs.config.packageOverrides = pkgs: {
              # sane-backends: Disable some dependencies of sane that don't (cross) build for arm
              # sane-backends: disable more dependencies that are not required
              # sane-backends: workaround for cross-compilation
              sane-backends = (pkgs.sane-backends.override {
                libjpeg = pkgs.libjpeg_turbo;
                libpng = null;
                libtiff = null;
                curl = null;
                libxml2 = null;
                poppler = null;
                libv4l = null;
                avahi = null;
                libieee1284 = null;
                libgphoto2 = null;
                net-snmp = null;
                systemd = null;
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
                bzip2 = null;
                zlib = null;
                libX11 = null;
                libXext = null;
                libXt = null;
                fontconfig = null;
                freetype = null;
                ghostscript = null;
                libjpeg = pkgs.libjpeg_turbo;
                djvulibre = null;
                lcms2 = null;
                openexr = null;
                libpng = null;
                librsvg = null;
                libtiff = null;
                libxml2 = null;
                openjpeg = null;
                libwebp = null;
                libheif = null;
              };
            };

            # Project specific configuration:
            networking.firewall.allowedTCPPorts = [ 80 ];
            services.lighttpd = {
              enable = true;
              document-root = "/data";
              extraConfig = ''
                dir-listing.activate = "enable"
              '';
            };

            services.scanbd.enable = true;
            services.udev.extraRules = ''
              SUBSYSTEM=="usb", ATTR{idVendor}=="04a9", ATTR{idProduct}=="1909", MODE="666"
            '';

            systemd.services.cleanup = {
              description = "cleanup data directory";
              startAt = "hourly";
              script = ''
                find /data -maxdepth 1 -ctime +40 -type f -exec rm \{\} \;
              '';
              serviceConfig.User = "root";
            };
          })

          ./scanbd
        ];
    };
}
