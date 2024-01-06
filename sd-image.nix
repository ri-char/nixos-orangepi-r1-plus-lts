# This module creates a bootable SD card image containing the given NixOS
# configuration. The generated image is MBR partitioned, with a root
# partition. The generated image is sized to fit its contents, and a boot
# script automatically resizes the root partition to fit the device on
# the first boot.
#
# The derivation for the SD image will be placed in
# config.system.build.sdImage
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
with lib; let
  rootfsImage = pkgs.callPackage (modulesPath + "/../lib/make-ext4-fs.nix") {
    inherit (config.sdImage) storePaths;
    compressImage = false;
    populateImageCommands = config.sdImage.populateRootCommands;
    volumeLabel = "NIXOS_SD";
  };

  compressedImageExtension = with config.sdImage;
    if compressImage
    then
      (
        if compressImageMethod == "zstd"
        then ".zst"
        else ".${compressImageMethod}"
      )
    else "";

  compressLevelCmdLineArg = with config.sdImage;
    lib.optionalString (compressImageLevel != null)
    "-${toString compressImageLevel}";
in {
  imports = [
    (modulesPath + "/profiles/all-hardware.nix")
  ];

  options.sdImage = {
    imageName = mkOption {
      default = "${config.sdImage.imageBaseName}-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}.img";
      description = ''
        Name of the generated image file.
      '';
    };

    imageBaseName = mkOption {
      default = "nixos-sd-image";
      description = ''
        Prefix of the name of the generated image file.
      '';
    };

    storePaths = mkOption {
      type = with types; listOf package;
      example = literalExpression "[ pkgs.stdenv ]";
      description = ''
        Derivations to be included in the Nix store in the generated SD image.
      '';
    };

    ubootPackage = mkOption {
      type = types.nullOr types.package;
      default = null;
      description = ''
        U-Boot package to use bootloader binary from.
      '';
    };

    partitionsOffset = mkOption {
      type = types.ints.unsigned;
      default = 8;
      description = ''
        Gap in front of the partitions, in mebibytes (1024×1024 bytes).
        Can be increased to make more space for boards requiring to dd u-boot
        SPL before actual partitions.

        Unless you are building your own images pre-configured with an
        installed U-Boot, you can instead opt to delete the existing `FIRMWARE`
        partition, which is used **only** for the Raspberry Pi family of
        hardware.
      '';
    };

    populateRootCommands = mkOption {
      example = literalExpression "''\${config.boot.loader.generic-extlinux-compatible.populateCmd} -c \${config.system.build.toplevel} -d ./files/boot''";
      description = ''
        Shell commands to populate the ./files directory.
        All files in that directory are copied to the
        root (/) partition on the SD image. Use this to
        populate the ./files/boot (/boot) directory.
      '';
    };

    postBuildCommands = mkOption {
      example = literalExpression "'' dd if=\${pkgs.myBootLoader}/SPL of=$img bs=1024 seek=1 conv=notrunc ''";
      default = "";
      description = ''
        Shell commands to run after the image is built.
        Can be used for boards requiring to dd u-boot SPL before actual partitions.
      '';
    };

    compressImage = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether the SD image should be compressed using
        <command>zstd</command> or <command>xz</command>.
      '';
    };

    compressImageMethod = mkOption {
      type = types.strMatching "^zstd|xz|lzma$";
      default = "zstd";
      description = ''
        The program which will be used to compress SD image.
      '';
    };

    compressImageLevel = mkOption {
      type = types.nullOr (types.ints.between 0 9);
      default = null;
      description = ''
        Image compression level to override default.
      '';
    };

    expandOnBoot = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to configure the sd image to expand it's partition on boot.
      '';
    };
  };

  config = {
    fileSystems = {
      "/" = {
        device = "/dev/disk/by-label/NIXOS_SD";
        fsType = "ext4";
      };
    };

    sdImage.storePaths = [config.system.build.toplevel];

    system.build.sdImage = pkgs.callPackage ({
      stdenv,
      dosfstools,
      e2fsprogs,
      mtools,
      libfaketime,
      util-linux,
      zstd,
      xz,
    }:
      stdenv.mkDerivation {
        name = config.sdImage.imageName;

        nativeBuildInputs = [dosfstools e2fsprogs mtools libfaketime util-linux zstd xz];

        buildInputs = lib.optional (config.sdImage.ubootPackage != null) config.sdImage.ubootPackage;

        buildCommand = ''
          mkdir -p $out/nix-support $out/sd-image
          export img=$out/sd-image/${config.sdImage.imageName}

          echo "${pkgs.stdenv.buildPlatform.system}" > $out/nix-support/system
          echo "file sd-image $img${compressedImageExtension}" >> $out/nix-support/hydra-build-products

          blockSize=512
          rootPartitionOffsetBlocks=$((${toString config.sdImage.partitionsOffset} * 1024 * 1024 / blockSize))
          rootPartitionOffsetBytes=$((rootPartitionOffsetBlocks * blockSize))

          # Create the image file sized to fit /boot/firmware and /, plus slack for the gap.
          rootPartitionSizeBlocks=$(du -B $blockSize --apparent-size ${rootfsImage} | awk '{ print $1 }')
          rootPartitionSizeBytes=$((rootPartitionSizeBlocks * blockSize))

          imageSizeBytes=$((rootPartitionOffsetBytes + rootPartitionSizeBytes))
          truncate -s $imageSizeBytes $img

          # The "bootable" partition is where u-boot will look file for the bootloader
          # information (dtbs, extlinux.conf file).
          sfdisk $img <<EOF
              label: dos

              start=$rootPartitionOffsetBlocks, type=linux, bootable
          EOF

          # Copy the rootfs into the SD image
          eval $(partx $img -o START,SECTORS --nr 1 --pairs)
          echo "Root partition: $START,$SECTORS"
          dd conv=notrunc if=${rootfsImage} of=$img seek=$START count=$SECTORS

          ${lib.optionalString (config.sdImage.ubootPackage != null) ''
            # Install U-Boot binary image
            echo "Install U-Boot: ${config.sdImage.ubootPackage}"
            dd if=${config.sdImage.ubootPackage}/idbloader.img of=$img seek=64 conv=notrunc
            dd if=${config.sdImage.ubootPackage}/u-boot.itb of=$img seek=16384 conv=notrunc
          ''}

          ${config.sdImage.postBuildCommands}
          ${lib.optionalString config.sdImage.compressImage
            (
              if config.sdImage.compressImageMethod == "zstd"
              then ''
                zstd -T$NIX_BUILD_CORES ${compressLevelCmdLineArg} --rm $img
              ''
              else ''
                xz -T$NIX_BUILD_CORES -F${config.sdImage.compressImageMethod} ${compressLevelCmdLineArg} $img
              ''
            )}

        '';
      }) {};

    boot.postBootCommands = lib.mkIf config.sdImage.expandOnBoot ''
      # On the first boot do some maintenance tasks
      if [ -f /nix-path-registration ]; then
        set -euo pipefail
        set -x
        # Figure out device names for the boot device and root filesystem.
        rootPart=$(${pkgs.util-linux}/bin/findmnt -n -o SOURCE /)
        bootDevice=$(lsblk -npo PKNAME $rootPart)
        partNum=$(lsblk -npo MAJ:MIN $rootPart | ${pkgs.gawk}/bin/awk -F: '{print $2}')

        # Resize the root partition and the filesystem to fit the disk
        echo ",+," | sfdisk -N$partNum --no-reread $bootDevice
        ${pkgs.parted}/bin/partprobe
        ${pkgs.e2fsprogs}/bin/resize2fs $rootPart

        # Register the contents of the initial Nix store
        ${config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration

        # nixos-rebuild also requires a "system" profile and an /etc/NIXOS tag.
        touch /etc/NIXOS
        ${config.nix.package.out}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system

        # Prevents this from running on later boots.
        rm -f /nix-path-registration
      fi
    '';
  };
}
