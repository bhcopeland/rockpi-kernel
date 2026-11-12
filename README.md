# rockpi-kernel

Mainline kernel for the Rock Pi 4 Plus that drives the ZeroMOD 480x1920 bar
display, built with tuxmake and installed alongside Armbian.

## Update the kernel

```
./build.sh            # resets ~/linux/linux-rockpi to BASE, applies patches/, runs tuxmake
./install-kernel.sh   # copies the build to the board (sudo asks there), then reboot it
ssh ben@192.168.0.71 sudo reboot
```

Builds go to `~/.cache/rockpi-kernel/out`. The kernel source is a detached
worktree of `~/linux/linux-stable`; `build.sh` recreates it if it is missing.

| File | Purpose |
| --- | --- |
| `BASE` | the upstream tag the patches apply to |
| `patches/` | the local kernel patches, in order |
| `rockpi.config` | kernel config, taken from Armbian's 6.18 config, `LOCALVERSION="-rockpi"` |

Overrides: `KERNEL_REPO`, `KERNEL_TREE`, `KERNEL_BASE`, `KERNEL_OUT`,
`DECK_HOST`, `DECK_SSH_OPTS`.

## Changing the patches

Commit the change in `~/linux/linux-rockpi`, then export the series again:

```
git -C ~/linux/linux-rockpi format-patch -o patches/ $(cat BASE)..HEAD
```

To move to a newer kernel, change `BASE` and fix any patch that no longer applies.

## Why the patches exist

The bar advertises a 66.28 MHz pixel clock. On mainline RK3399:

1. VPLL only offers rates from a fixed table, so the mode was rejected as
   `MODE_NOCLOCK`. `0001` adds an exact integer-mode 66.28 MHz entry.
2. VOPB's pixel clock defaulted to GPLL divided down (66.0 MHz), which the
   bar's bridge cannot hold. `0002` feeds `DCLK_VOP0_DIV` from VPLL and
   disables the unused VOPL.
3. The VOP rounds the mode clock before VPLL is set, and the divider could not
   ask VPLL to change, so the clock was clamped. `0003` lets the divider set
   VPLL's rate without ever reparenting to the shared CPLL or GPLL.
4. `0004` stops the PLL restore path recursing until the stack overflows when
   a PLL fails to lock, which panicked the board during this work.

`0004` is the one candidate for upstream as it stands.

## If a kernel does not boot

Armbian's own kernel stays in `/boot`. On the serial console (1500000 baud),
stop U-Boot at "Hit any key to stop autoboot" and enter, one line at a time:

```
setenv bootargs root=UUID=76f662ee-6025-432d-8863-d33d0e091c54 rootwait rootfstype=ext4 console=ttyS2,1500000 console=tty1 consoleblank=0 loglevel=1
load mmc 0:1 ${kernel_addr_r} /boot/vmlinuz-6.18.63-current-rockchip64
load mmc 0:1 ${fdt_addr_r} /boot/dtb-6.18.63-current-rockchip64/rockchip/rk3399-rock-pi-4b.dtb
load mmc 0:1 ${ramdisk_addr_r} /boot/uInitrd-6.18.63-current-rockchip64
booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}
```

Then make Armbian's kernel the default again:

```
cd /boot && sudo ln -sfn vmlinuz-6.18.63-current-rockchip64 Image \
  && sudo ln -sfn uInitrd-6.18.63-current-rockchip64 uInitrd \
  && sudo ln -sfn dtb-6.18.63-current-rockchip64 dtb
```
