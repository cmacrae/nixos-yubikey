{
  description = "Create NixOS ISO images for use with initializing YubiKeys";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-20.09";
    drduh-gpg-conf = {
      url = "github:drduh/config";
      flake = false;
    };
    drduh-yubikey-guide = {
      url = "github:drduh/yubikey-guide";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, drduh-gpg-conf, drduh-yubikey-guide }: {

    iso = self.nixosConfigurations.yubikey.config.system.build.isoImage;
    nixosConfigurations = {
      yubikey = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        
        modules = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-base.nix"
          (

            let
              pkgs = import nixpkgs { system = "x86_64-linux"; };
              gpg-agent-conf = pkgs.writeText "gpg-agent.conf" ''
                pinentry-program ${pkgs.pinentry-curses}/bin/pinentry-curses
              '';

              yk-scripts  = pkgs.callPackage pkgs/yk-scripts  { };
              gpg-scripts = pkgs.callPackage pkgs/gpg-scripts { };

            in {   
              # Image properties
              fonts.fontconfig.enable = false;
              isoImage.edition = "yubikey";
              isoImage.isoBaseName = "nixos-yubikey";
              isoImage.appendToMenuLabel = "Live YubiKey Environment";
              isoImage.makeEfiBootable = true;
              isoImage.makeUsbBootable = true;

              # Always copytoram so that, if the image is booted from, e.g., a
              # USB stick, nothing is mistakenly written to persistent storage.
              boot.kernelParams = [ "copytoram" ];

              ## Required packages and services.
              #
              # ref: https://rzetterberg.github.io/yubikey-gpg-nixos.html
              environment.systemPackages = with pkgs; [
                cfssl
                cryptsetup
                diceware
                ent
                git
                gitAndTools.git-extras
                gnupg
                gpg-scripts
                # FIXME: Marked as broken
                # (haskell.lib.justStaticExecutables haskellPackages.hopenpgp-tools)
                paperkey
                parted
                pcsclite
                pcsctools
                pgpdump
                pinentry-curses
                pwgen
                yk-scripts
                yubikey-manager
                yubikey-personalization
              ];

              services.udev.packages = [ pkgs.yubikey-personalization ];
              services.pcscd.enable = true;

              # Make sure networking is disabled in every way possible.
              boot.initrd.network.enable = false;
              networking.dhcpcd.enable = false;
              networking.dhcpcd.allowInterfaces = [];
              networking.firewall.enable = true;
              networking.useDHCP = false;
              networking.useNetworkd = false;
              networking.wireless.enable = false;

              ## Make it easy to tell which nixpkgs the image was built from.
              #
              # Most of the following config is thanks to Graham Christensen,
              # from:
              # https://github.com/grahamc/network/blob/1d73f673b05a7f976d82ae0e0e61a65d045b3704/modules/standard/default.nix#L56
              nix = {
                useSandbox = true;
                nixPath = [
                  # Copy the channel version from the deploy host to the target
                  "nixpkgs=/run/current-system/nixpkgs"
                ];
              };

              system.extraSystemBuilderCmds = ''
                ln -sv ${pkgs.path} $out/nixpkgs
              '';

              environment.etc.host-nix-channel.source = pkgs.path;

              ## Secure defaults.
              boot.cleanTmpDir = true;
              boot.kernel.sysctl = {
                "kernel.unprivileged_bpf_disabled" = 1;
              };

              ## Set up the shell for making keys.
              environment.interactiveShellInit = ''
                unset HISTFILE
                export GNUPGHOME=/run/user/$(id -u)/gnupg
                [ -d $GNUPGHOME ] || install -m 0700 -d $GNUPGHOME
                cp ${drduh-gpg-conf}/gpg.conf $GNUPGHOME/gpg.conf
                cp ${gpg-agent-conf} $GNUPGHOME/gpg-agent.conf
                echo "\$GNUPGHOME is $GNUPGHOME"

                cp ${drduh-yubikey-guide}/README.md $HOME/yubikey-guide.md
                echo "Dr Duh's YubiKey Guide is available in $HOME/yubikey-guide.md"
              '';
            })
        ];
      };
    };
  };
}
