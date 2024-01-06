{
  config,
  modulesPath,
  lib,
  pkgs,
  ...
}: {
  imports = [
    (modulesPath + "/profiles/base.nix")
  ];

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  boot.kernelParams = ["earlycon" "console=ttyS2,1500000" "consoleblank=0"];
  boot.supportedFilesystems = lib.mkForce ["ext4" "vfat" "ntfs"];

  sdImage = {
    compressImage = false;
    imageBaseName = "nixos-sd-image-orange-pi-r1-plus-lts";
    ubootPackage = pkgs.buildUBoot {
      defconfig = "orangepi-r1-plus-lts-rk3328_defconfig";
      extraMeta = {
        platforms = ["aarch64-linux"];
      };
      src = pkgs.fetchgit {
        url = "https://source.denx.de/u-boot/u-boot.git";
        rev = "v2024.01-rc6";
        sha256 = "sha256-fdgN6gVf2BPFnqvrdcT0WnkaB1r2s5K9gabdn+a4Djo=";
      };
      makeFlags = [
        "CROSS_COMPILE=${pkgs.stdenv.cc.targetPrefix}"
      ];
      version = "v2024.01-rc6";
      patches = [];

      enableParallelBuilding = true;

      BL31 = "${pkgs.armTrustedFirmwareRK3328}/bl31.elf";
      filesToInstall = ["u-boot.itb" "idbloader.img"];
    };
    partitionsOffset = 16;
    populateRootCommands = ''
      mkdir -p ./files/boot
      ${config.boot.loader.generic-extlinux-compatible.populateCmd} -c ${config.system.build.toplevel} -d ./files/boot
    '';
  };
}
