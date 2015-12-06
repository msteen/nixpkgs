{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.boot.initrd.network;
  authorizedKeys = ''
    ${concatStringsSep "\n" cfg.ssh.authorizedKeys.keys}
    ${concatMapStrings (f: readFile f + "\n") cfg.ssh.authorizedKeys.keyFiles}
  '';
  rootAuthorizedKeys = config.users.extraUsers.root.openssh.authorizedKeys;

in {

  options = {

    boot.initrd.network.enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Add network connectivity support to initrd.

        Network options are configured via <literal>ip</literal> kernel
        option, according to the kernel documentation.
      '';
    };

    boot.initrd.network.ssh.enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Start SSH service during initrd boot. It can be used to debug failing
        boot on a remote server, enter pasphrase for an encrypted partition etc.
        Service is killed when stage-1 boot is finished.
      '';
    };

    boot.initrd.network.setupDependencies = mkOption {
      type = types.str;
      default = "";
      example = ''
        copy_bin_and_libs ${pkgs.wpa_supplicant}/bin/wpa_supplicant
      '';
      description = ''
        The binaries and libraries on which the network setup depends.
      '';
    };

    boot.initrd.network.setup = mkOption {
      type = types.str;
      example = ''
        ip link set eth0 up && hasNetwork=1
        ip addr add 192.168.0.101/24 dev eth0
        ip route add via 192.168.0.1 dev eth0
      '';
      description = ''
        The code that sets up the network. The <literal>hasNetwork</literal>
        variable has to be set to <literal>1</literal> if a network connection
        has succesfully been made.
      '';
    };

    boot.initrd.network.ssh.port = mkOption {
      type = types.int;
      default = 22;
      description = ''
        Port on which SSH initrd service should listen.
      '';
    };

    boot.initrd.network.ssh.shell = mkOption {
      type = types.str;
      default = "/bin/ash";
      description = ''
        Login shell of the remote user. Can be used to limit actions user can do.
      '';
    };

    boot.initrd.network.ssh.hostRSAKey = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        RSA SSH private key file in the Dropbear format.

        WARNING: This key is contained insecurely in the global Nix store. Do NOT
        use your regular SSH host private keys for this purpose or you'll expose
        them to regular users!
      '';
    };

    boot.initrd.network.ssh.hostDSSKey = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        DSS SSH private key file in the Dropbear format.

        WARNING: This key is contained insecurely in the global Nix store. Do NOT
        use your regular SSH host private keys for this purpose or you'll expose
        them to regular users!
      '';
    };

    boot.initrd.network.ssh.hostECDSAKey = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        ECDSA SSH private key file in the Dropbear format.

        WARNING: This key is contained insecurely in the global Nix store. Do NOT
        use your regular SSH host private keys for this purpose or you'll expose
        them to regular users!
      '';
    };

    boot.initrd.network.ssh.authorizedKeys = {
      keys = mkOption {
        type = types.listOf types.str;
        default = rootAuthorizedKeys.keys;
        description = ''
          A list of verbatim OpenSSH public keys that are authorized access
          to the root user on initrd. The keys are added to a file that the SSH
          daemon reads in addition to the the user's authorized_keys file.
          You can combine the <literal>keys</literal> and
          <literal>keyFiles</literal> options.
        '';
      };

      keyFiles = mkOption {
        type = types.listOf types.path;
        default = rootAuthorizedKeys.keyFiles;
        description = ''
          A list of files each containing one OpenSSH public key that are
          authorized accesss to the root user on initrd. The contents of the
          files are read at build time and added to a file that the SSH daemon
          reads in addition to the the user's authorized_keys file. You can
          combine the <literal>keyFiles</literal> and <literal>keys</literal>
          options.
        '';
      };
    };

  };

  config = mkIf cfg.enable {

    boot.initrd.kernelModules = [ "af_packet" ];

    boot.initrd.extraUtilsCommands =
      cfg.setupDependencies + optionalString cfg.ssh.enable ''
      copy_bin_and_libs ${pkgs.dropbear}/bin/dropbear

      cp -pv ${pkgs.glibc}/lib/libnss_files.so.* $out/lib
    '';

    boot.initrd.extraUtilsCommandsTest = optionalString cfg.ssh.enable ''
      $out/bin/dropbear -V
    '';

    boot.initrd.postEarlyDeviceCommands =
      cfg.setup + optionalString cfg.ssh.enable ''
      if [ -n "$hasNetwork" ]; then
        mkdir /dev/pts
        mount -t devpts devpts /dev/pts

        mkdir -p /etc
        echo 'root:x:0:0:root:/root:${cfg.ssh.shell}' > /etc/passwd
        echo '${cfg.ssh.shell}' > /etc/shells
        echo 'passwd: files' > /etc/nsswitch.conf

        mkdir -p /var/log
        touch /var/log/lastlog

        mkdir -p /etc/dropbear
        ${optionalString (cfg.ssh.hostRSAKey != null) "ln -s ${cfg.ssh.hostRSAKey} /etc/dropbear/dropbear_rsa_host_key"}
        ${optionalString (cfg.ssh.hostDSSKey != null) "ln -s ${cfg.ssh.hostDSSKey} /etc/dropbear/dropbear_dss_host_key"}
        ${optionalString (cfg.ssh.hostECDSAKey != null) "ln -s ${cfg.ssh.hostECDSAKey} /etc/dropbear/dropbear_ecdsa_host_key"}

        mkdir -p /root/.ssh
        echo '${escape ["'"] authorizedKeys}' > /root/.ssh/authorized_keys

        dropbear -s -j -k -E -m -p ${toString cfg.ssh.port}
      fi
    '';

    boot.initrd.postDeviceCommands = ''
      umount -l /dev/pts
    '';

  };
}
