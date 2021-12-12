{
  description = "raspberry pi image for scanner box";
  inputs.template.url = "path:../template";

  outputs = { self, template }:
    let settings = builtins.fromJSON (builtins.readFile ./settings.json);
    in
    {
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
              # scanbd: install dbus policy file and rename user to scanner (but dbus is not used)
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

              # pngquant: it assumes sse availability from host cpu
              pngquant = pkgs.pngquant.overrideAttrs
                (old: { configureFlags = "--disable-sse"; });

              # gumbo: somehow it does not find itself the path to m4
              gumbo = pkgs.gumbo.overrideAttrs (old: {
                buildInputs = [ ];
                M4 = "${pkgs.buildPackages.m4}/bin/m4";
                nativeBuildInputs =
                  [ pkgs.autoconf pkgs.automake pkgs.libtool pkgs.m4 ];
              });

              python3 = pkgs.python3.override {
                packageOverrides = self: super: {
                  # pybind11 does not discover the host python interpreter
                  pybind11 = super.pybind11.overridePythonAttrs (old: {
                    nativeBuildInputs =
                      [ pkgs.buildPackages.cmake pkgs.python3 ];
                    cmakeFlags = old.cmakeFlags ++ [
                      "-DPYTHON_EXECUTABLE:FILEPATH=${pkgs.buildPackages.python3}/bin/python"
                    ];
                  });
                  ocrmypdf = super.ocrmypdf.overrideAttrs (old: {
                    nativeBuildInputs = old.nativeBuildInputs
                      ++ [ pkgs.buildPackages.python3Packages.cffi ];
                  });
                };
              };

              # qpdf: on cross compile the check to find random device fails, force /dev/urandom
              qpdf = pkgs.qpdf.overrideAttrs
                (old: { configureFlags = "--with-random=/dev/urandom"; });

              # leptonica: reduce size by disabling unused features
              leptonica = pkgs.leptonica.override {
                giflib = null;
                gnuplot = null;
                libpng = null;
                libtiff = null;
                libwebp = null;
              };

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

              # ghostscript: needs to compile something for the host machine during build process
              ghostscript = (pkgs.ghostscript.override {
                xlibsWrapper = null;
                x11Support = false;
                cups = null;
                cupsSupport = false;
                openssl = null;
              });

              # unbound: cannot execute "unittest" (check) with binary compiled for other architecture
              unbound = pkgs.unbound.overrideAttrs (old: {
                preFixup = "";
              });

              # mupdf: expects the native version of pkg-config under the name pkg-config and not with platform prefix
              mupdf = (pkgs.mupdf.overrideAttrs (old: {
                nativeBuildInputs = old.nativeBuildInputs ++ [
                  (pkgs.writeScriptBin "pkg-config"
                    "${pkgs.buildPackages.pkg-config}/bin/${pkgs.stdenv.targetPlatform.config}-pkg-config $*")
                ];
              })).override {
                enableX11 = false;
                enableGL = false;
                enableCurl = false;
              };

              # unpaper executes xsltproc during build process
              unpaper = pkgs.unpaper.overrideAttrs (old: {
                nativeBuildInputs = [
                  pkgs.buildPackages.pkg-config
                  pkgs.buildPackages.libxslt.bin
                ];
              });

              # gmp: for some reason m4 needs to specified like this from buildPackages explicitly...
              gmp = pkgs.gmp.overrideAttrs (old: {
                nativeBuildInputs = old.nativeBuildInputs
                  ++ [ pkgs.buildPackages.m4 ];
                preConfigure = ""; # not sure what this changes
              });

              # tesseract4: just german language to save space
              tesseract4 = pkgs.tesseract4.override {
                enableLanguages = [ "deu" "eng" ];
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
            environment.systemPackages = [ pkgs.ocrmypdf ];

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
