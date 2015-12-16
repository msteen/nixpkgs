{ config, lib, pkgs, ... }:

with lib;

let

  inherit (pkgs) ntp;

  cfg = config.services.ntp;

  stateDir = "/var/lib/ntp";

  ntpUser = "ntp";

  configFile = pkgs.writeText "ntp.conf" ''
    driftfile ${stateDir}/ntp.drift

    restrict 127.0.0.1
    restrict -6 ::1

    ${toString (map (server: "server " + server + " iburst\n") cfg.servers)}

    ${cfg.extraConfig}
  '';

in

{

  ###### interface

  options = {

    services.ntp = {

      enable = mkOption {
        type = types.bool;
        default = !config.boot.isContainer;
        description = ''
          Whether to synchronise your machine's time using the NTP
          protocol.
        '';
      };

      servers = mkOption {
        type = types.listOf types.string;
        default = [
          "0.nixos.pool.ntp.org"
          "1.nixos.pool.ntp.org"
          "2.nixos.pool.ntp.org"
          "3.nixos.pool.ntp.org"
        ];
        description = ''
          The set of NTP servers from which to synchronise.
        '';
      };

      enableIPv6 = mkOption {
        type = types.bool;
        default = config.networking.enableIPv6;
        description = ''
          Whether to enable support for IPv6.
        '';
      };

      extraConfig = mkOption {
        type = with types; lines;
        default = "";
        description = ''
          Additional text appended to <filename>ntp.conf</filename>.
        '';
      };

      extraOptions = mkOption {
        type = with types; string;
        default = "";
        description = ''
          Extra options used when launching ntpd.
        '';
      };

    };

  };


  ###### implementation

  config = mkIf config.services.ntp.enable {

    # Make tools such as ntpq available in the system path.
    environment.systemPackages = [ pkgs.ntp ];

    users.extraUsers = singleton {
      name = ntpUser;
      uid = config.ids.uids.ntp;
      description = "NTP daemon user";
      home = stateDir;
    };

    systemd.services.ntpd = {
      description = "NTP Daemon";
      wants = [ "network-online.target" ];
      after = [ "dnsmasq.service" "bind.service" "network-online.target" ];
      preStart = ''
        mkdir -m 0755 -p ${stateDir}
        chown ${ntpUser} ${stateDir}
      '';
      serviceConfig = {
        ExecStart = "@${ntp}/bin/ntpd ntpd ${optionalString (!cfg.enableIPv6) "-4"} -g -c ${configFile} -u ${ntpUser}:nogroup ${cfg.extraOptions}";
        Type = "forking";
      };
      wantedBy = [ "multi-user.target" ];
    };

  };

}

