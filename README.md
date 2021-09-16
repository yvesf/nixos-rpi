# build image for sd-card

```shell
$ TARGET=rpi-solar
$ nix build path:.#nixosConfigurations.${TARGET}.sdImage
$ sudo dd bs=1024 if="$(readlink -f result/sd-image/nixos-sd-image-*.img)" status=progress conv=fsync of=/dev/DEVICE
```

# remote update with nixos-rebuild

```shell
$ nixos-rebuild --use-remote-sudo --target-host jack@${TARGET} --build-host localhost switch --flake path:.#${TARGET}

building the system configuration...
copying 1 paths...
activating the configuration...
setting up /etc...
setting up tmpfiles
```

