{
  description = "Development shell and PS3 kernel cross-compilation for PowerPC 64-bit";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    ps3-linux = {
      url = "git+https://git.kernel.org/pub/scm/linux/kernel/git/geoff/ps3-linux.git?ref=ps3-queue-v6.13";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      ps3-linux,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        # Create a cross-compilation package set for ppc64 (big-endian)
        pkgsCross = pkgs.pkgsCross.ppc64;

        # Build PS3 kernel using manual configuration
        ps3Kernel = pkgsCross.stdenv.mkDerivation {
          pname = "linux-ps3";
          version = "6.13.0-rc1";

          src = ps3-linux;

          nativeBuildInputs = with pkgs; [
            pkgsCross.stdenv.cc
            gnumake
            gcc
            flex
            bison
            bc
            openssl
            perl
            elfutils
          ];

          buildInputs = with pkgs; [
            openssl
          ];

          dontPatchELF = true;
          STRIP = "${pkgsCross.stdenv.cc.targetPrefix}strip";

          makeFlags = [
            "ARCH=powerpc"
            "CROSS_COMPILE=${pkgsCross.stdenv.cc.targetPrefix}"
          ];

          configurePhase = ''
            # Use the PS3 defconfig
            make $makeFlags ps3_defconfig
          '';

          buildPhase = ''
            make $makeFlags -j$NIX_BUILD_CORES
          '';

          installPhase = ''
            mkdir -p $out/boot
            kernelVersion=$(make -s kernelrelease)
            cp arch/powerpc/boot/zImage $out/boot/vmlinuz
            cp .config $out/boot/config-$kernelVersion
            cp System.map $out/boot/System.map
            make $makeFlags INSTALL_MOD_PATH="$out" modules_install
            rm -f $out/lib/modules/*/build
            rm -f $out/lib/modules/*/source
          '';
        };
      in
      {
        packages = {
          ps3-kernel = ps3Kernel;
          default = ps3Kernel;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            debootstrap
            qemu_full
            rsync
          ];

          shellHook = ''
            # https://blog.paulsajna.com/ps3-linux/
            echo "You can run debootstrap commands."
            echo "sudo mkdir -p <dst>/nix/store"
            echo "sudo mount --bind /nix/store <dst>/nix/store"
            echo "sudo debootstrap --arch=ppc64 --variant=buildd --extractor=ar sid <dst> https://deb.debian.org/debian-ports"
            echo "sudo rsync -avh --progress result/ <dst>"
            echo "sudo mount -t proc proc <dst>/proc"
            echo "sudo chroot <dst> /bin/bash"
            echo "export PATH=/usr/bin:/usr/sbin"
            echo "apt install debian-ports-archive-keyring"
            echo "apt update"
            echo "apt install sudo vim git build-essential curl wget git ssh initramfs-tools locales tasksel"
            echo "adduser <username>"
            echo "usermod -aG sudo <username?"
            echo "dpkg-reconfigure locales"
            echo "Create fstab"
            echo "Create petitboot.conf in /etc/petitboot/"
            echo "tasksel"
            echo "mkinitramfs -k -o /boot/initrd.img 6.13.0-rc1 # Or other kernel version depending on kernel build"
          '';
        };
      }
    );
}
