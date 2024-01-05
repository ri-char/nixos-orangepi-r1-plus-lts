
# NixOS image for OrangePi R1 Plus Lts

This repo is forked from [gytis-ivaskevicius/orangepi-r1-plus-nixos-image](https://github.com/gytis-ivaskevicius/orangepi-r1-plus-nixos-image), but for OrangePi R1 Plus Lts.

You can configure your own image by editing `config.nix` file.

Installation steps:
```bash
nix build
sudo dd if=./result/sd-image/*.img of=/dev/SD_CARD iflag=direct oflag=direct bs=16M status=progress
```

Update remote machine:
```bash
UPDATE_TARGET=192.168.0.xxx
nixos-rebuild switch --target-host $UPDATE_TARGET --flake .#orangepi-r1-plus-lts-config
```
