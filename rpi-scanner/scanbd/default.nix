{ config, lib, pkgs, ... }:

with lib;

let
  configDir = "/etc/scanbd";

  scanbdConf = pkgs.writeText "scanbd.conf" ''
    global {
      debug = true
      debug-level = ${toString config.services.scanbd.debugLevel}
      user = scanner
      group = scanner
      scriptdir = ${configDir}/scripts
      pidfile = /var/run/scanbd.pid
      timeout = 500 #ms
      environment {
        device = "SCANBD_DEVICE"
        action = "SCANBD_ACTION"
      }

      multiple_actions = true
      action scan {
        filter = "^scan.*"
        numerical-trigger {
          from-value = 1
          to-value   = 0
        }
        script = "scan.script"
      }
      action copy {
        filter = "^copy.*"
        numerical-trigger {
          from-value = 1
          to-value   = 0
        }
        script = "scan.script"
      }
      action file {
        filter = "^file.*"
        numerical-trigger {
          from-value = 1
          to-value   = 0
        }
        script = "scan.script"
      }
      action email {
        filter = "^email.*"
        numerical-trigger {
          from-value = 1
          to-value   = 0
        }
        script = "scan.script"
      }
    }
  '';

  execute-scan = pkgs.writeScript "execute-scan.sh" ''
    #! ${pkgs.bash}/bin/bash
    export PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.sane-backends
        pkgs.imagemagick
        pkgs.ocrmypdf
      ]
    }
    export SANE_CONFIG_DIR=/etc/scanbd
    echo "Action: $SCANBD_ACTION on $SCANBD_DEVICE"
    set -x

    OUTFILE="/data/''${SCANBD_ACTION}_$(date '+%Y-%m-%d_%H-%M-%S')"
    TMPFILE=$(mktemp)

    case "$SCANBD_ACTION" in
      scan)
        scanimage --format pnm --resolution 600 --mode Color -l 0 -t 0 -x 210mm -y 297mm |
          convert pnm:- -rotate 180 jpg:"$OUTFILE.jpg"
        chmod 664 $OUTFILE.jpg
        ;;
      copy)
        scanimage --format pnm --resolution 100 --mode Color -l 0 -t 0 -x 210mm -y 297mm |
          convert pnm:- -rotate 180 jpg:"$OUTFILE.jpg"
        chmod 664 $OUTFILE.jpg
        ;;
      file)
        scanimage --format pnm --resolution 300 --mode Color -l 0 -t 0 -x 210mm -y 297mm |
          convert pnm:- -rotate 180 -compress jpeg -quality 80 -page A4 pdf:"$OUTFILE.pdf"
        chmod 0664 $OUTFILE.pdf
        ;;
      email)
        # broken because dependencies of ocrmypdf don't cross-compile yet
        scanimage --format pnm --resolution 300 --mode Gray -l 0 -t 0 -x 210mm -y 297mm |
          convert pnm:- -rotate 180 -compress jpeg -quality 80 -page A4 pdf:"$OUTFILE.part.pdf"
        ocrmypdf -c -l deu --tesseract-timeout 720 "$OUTFILE.part.pdf" "$OUTFILE.pdf"
        rm "$OUTFILE.part.pdf"
        ;;
      *)
        echo "Invalid action $SCANBD_ACTION"
        ;;
    esac
  '';
in {
  options = {
    services.scanbd.enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable support for scanbd (scanner button daemon).

        <note><para>
          If scanbd is enabled, then saned must be disabled.
        </para></note>
      '';
    };

    services.scanbd.debugLevel = mkOption {
      type = types.int;
      default = 2;
      example = "";
      description = ''
        Debug logging (1=error, 2=warn, 3=info, 4-7=debug)
      '';
    };
  };

  config = mkIf config.services.scanbd.enable {
    users.groups.scanner.gid = config.ids.gids.scanner;
    users.users.scanner.uid = config.ids.uids.scanner;
    users.users.scanner.group = "scanner";

    environment.etc."scanbd/scanbd.conf".source = scanbdConf;
    environment.etc."scanbd/scripts/scan.script".source = execute-scan;
    environment.etc."scanbd/scripts/test.script".source =
      "${pkgs.scanbd}/etc/scanbd/test.script";
    environment.etc."scanbd/dll.conf".source =
      "${pkgs.sane-backends}/etc/sane.d/dll.conf";
    environment.etc."scanbd/genesys.conf".source =
      "${pkgs.sane-backends}/etc/sane.d/genesys.conf";

    services.dbus.packages = [ pkgs.scanbd ];
    
    systemd.services.scanbd = {
      enable = true;
      description = "Scanner button polling service";
      documentation = [
        "https://sourceforge.net/p/scanbd/code/HEAD/tree/releases/1.5.1/integration/systemd/README.systemd"
      ];
      script = "${pkgs.scanbd}/bin/scanbd -c ${configDir}/scanbd.conf -f";
      environment.SANE_CONFIG_DIR = configDir;
      wantedBy = [ "multi-user.target" ];
      aliases = [ "dbus-de.kmux.scanbd.server.service" ];
    };
  };
}
