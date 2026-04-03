# bootc-fedora-gnome-macbookair

Immutable Fedora 44 image with GNOME Shell, tailored for MacBook Air hardware. Automated daily builds via GitHub Actions.

> **Tested on:** MacBook Air A1466 (Mid 2012 – 2017)

## Architecture

| Component | Details |
|-----------|---------|
| **Base** | Fedora Linux 44 (`quay.io/fedora/fedora-bootc:44`) |
| **Desktop** | GNOME Shell (minimal install, no weak deps) |
| **WiFi** | Broadcom `akmod-wl` via RPMFusion Non-Free |
| **Camera** | FaceTimeHD via [mulderje/facetimehd-kmod](https://copr.fedorainfracloud.org/coprs/mulderje/facetimehd-kmod/) COPR + [firmware](https://github.com/patjak/facetimehd-firmware) |
| **Filesystem** | Btrfs with subvolumes (root, var, home) |
| **Timezone** | America/Santiago (Chile) |
| **Flatpaks** | User-level (`--user`) via first-login bootstrap |

## File Structure

| File | Purpose |
|------|---------|
| `Containerfile` | Multi-stage build: kernel modules in builder → final image |
| `packages.rpm` | RPM packages to install (one per line) |
| `post-install.sh` | First-login script: installs Flatpaks as `--user` |
| `post-install.service` | Systemd **user** service (runs on first login) |
| `config.toml` | Anaconda kickstart config for ISO generation |
| `hid-apple.conf` | MacBook keyboard driver configuration |
| `dracut-facetimehd.conf` | Includes FaceTimeHD firmware in initramfs |
| `suspend-fix.service` | Fixes MacBook spurious wakeup from suspend |
| `powertop.service` | Battery optimization via PowerTOP auto-tune |
| `.github/workflows/build-image.yml` | Daily CI/CD build (06:45 UTC) |

## MacBook-Specific Features

- **Broadcom WiFi**: `kmod-wl` built against the image kernel, ready to use out of the box.
- **FaceTimeHD Camera**: Kernel module + firmware baked into the image.
- **Keyboard**: `hid_apple` configured with `fnmode=2` (F-keys default) and `iso_layout=0` (ANSI).
- **Suspend Fix**: Disables XHC1/LID0 ACPI wakeup to prevent spurious wake from sleep.
- **Battery**: PowerTOP auto-tune runs on every boot.
- **Ambient Light**: [macbook-lighter](https://github.com/harttle/macbook-lighter) for automatic screen/keyboard backlight.

## Flatpak Applications (user-level)

Flatpak applications are installed automatically as `--user` on the first graphical login via a systemd user service (`post-install.service`). See [`post-install.sh`](post-install.sh) for the full list of applications.

## How to Update

The image is rebuilt daily at 02:00 UTC time.

```bash
# Check for updates
sudo bootc upgrade --check

# Apply upgrade
sudo bootc upgrade

# After reboot, verify updated packages
rpm-ostree db diff

# Reboot to apply
sudo reboot
```

## How to Build Locally

### Build the container image

```bash
git clone https://github.com/CleoMenezesJr/bootc-fedora-gnome-macbookair.git
cd bootc-fedora-gnome-macbookair
mkdir -p output
sudo podman build -t bootc-fedora-gnome-macbookair -f Containerfile
```

### Create an installation ISO

```bash
sudo podman run \
    --rm -it --privileged \
    --pull=newer \
    --security-opt label=type:unconfined_t \
    -v ./output:/output \
    -v ./config.toml:/config.toml:ro \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    quay.io/centos-bootc/bootc-image-builder:latest \
    --type anaconda-iso \
    --rootfs btrfs \
    localhost/bootc-fedora-gnome-macbookair
```

The resulting ISO will be at `output/bootiso/install.iso`.

## Maintenance

```bash
# Check current version
bootc status

# Rollback to previous version
sudo bootc rollback

# Switch to this image (first time)
sudo bootc switch ghcr.io/CleoMenezesJr/bootc-fedora-gnome-macbookair:latest
```

## Credits

This project was inspired by and based on the work from [Ferlinuxdebian/bootc-gnome-minimal](https://github.com/Ferlinuxdebian/bootc-gnome-minimal). Special thanks to the original author for the foundational bootc configuration and workflow.
