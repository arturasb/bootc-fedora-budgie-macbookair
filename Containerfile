# 1. Base: Use official Fedora 44 bootc
FROM quay.io/fedora/fedora-bootc:44

RUN set -euo pipefail

# 2. Setup Repositories
RUN dnf5 -y --refresh install \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-44.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-44.noarch.rpm" && \
    # Direct download of COPR repo file to avoid dnf5 plugin issues
    curl -L -o /etc/yum.repos.d/_copr_mulderje-facetimehd-kmod.repo \
    https://copr.fedorainfracloud.org/coprs/mulderje/facetimehd-kmod/repo/fedora-44/mulderje-facetimehd-kmod-fedora-44.repo

# 3. Install Budgie Desktop (Onyx) and Essential Tools
RUN dnf5 -y --setopt=install_weak_deps=True group install budgie-desktop && \
    dnf5 -y --refresh install \
    gnome-terminal nautilus gtklock polkit upower sddm \
    plymouth plymouth-system-theme plymouth-graphics-libs \
    gnome-software gnome-software-rpm-ostree gnome-settings-daemon \
    pipewire pipewire-pulseaudio wireplumber network-manager-applet fedora-release-budgie-atomic \
    firewalld firewall-config \
    flatpak distrobox \
    wireguard-tools systemd-resolved nm-connection-editor \
    glibc-all-langpacks intel-media-driver mc btop libva-utils zram zip unzip usbutils lm_sensors powertop ibus-gtk4 && \
    dnf5 clean all

# 4. MacBook Hardware: Drivers & Thermal Management
# Pridėtas explicit branduolio atnaujinimas ir papildomi įrankiai (elfutils, bc) modulių pasirašymui/kompiliavimui
RUN dnf5 -y --refresh install \
    broadcom-wl akmod-wl \
    akmod-facetimehd facetimehd-kmod-common \
    kernel kernel-core kernel-devel akmods wget git make gcc curl xz cpio \
    elfutils-libelf-devel bc \
    NetworkManager-wifi && \
    dnf5 clean all

# 4.1. Build Akmods for the specific kernel in the image
# Patobulintas skriptas, kuris automatiškai suranda tikslią įdiegtos kernel-devel versiją
RUN KERNEL_VERSION=$(rpm -q kernel-devel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' | head -n 1) && \
    echo "▸ Building modules for kernel version: ${KERNEL_VERSION}" && \
    akmods --force --kernels "${KERNEL_VERSION}" --kmod facetimehd && \
    akmods --force --kernels "${KERNEL_VERSION}" --kmod wl || \
    (cat /var/cache/akmods/facetimehd/*.log /var/cache/akmods/wl/*.log 2>/dev/null && exit 1)

# 5. Extract FaceTimeHD Firmware from Apple BootCamp Driver
# Ištaisyta nedidelė spausdinimo klaida rm -rf /tmp/tmp/... -> /tmp/...
RUN git clone --depth 1 "https://github.com/patjak/facetimehd-firmware.git" /tmp/facetimehd-firmware && \
    cd /tmp/facetimehd-firmware && \
    make && \
    make install && \
    cd / && \
    rm -rf /tmp/facetimehd-firmware

# 5.1. Install mbpfan v2.4.0 from source (Kompiliuojame tiesiai į /usr)
RUN echo "▸ Installing mbpfan v2.4.0 from source" && \
    git clone --depth 1 --branch v2.4.0 https://github.com/linux-on-mac/mbpfan.git /tmp/mbpfan  && \
    cd /tmp/mbpfan && \
    make && \
    # mbpfan Makefile pagal nutylėjimą diegia į /usr/sbin, o konfigūraciją į /etc, kas yra gerai
    make install && \
    # Užtikriname, kad serviso failas būtų teisingoje systemd direktorijoje (/usr/lib, o ne /lib)
    cp -v mbpfan.service /usr/lib/systemd/system/mbpfan.service && \
    cd /  && \
    rm -rf /tmp/mbpfan

# 5.2. Bootc geriausia praktika: Writable direktorijų valdymas per tmpfiles.d
# Užuot keitę /usr/local struktūrą kompiliavimo metu, nurodome sistemai paruošti aplinką vykdymo metu.
RUN mkdir -p /usr/lib/tmpfiles.d/ && \
    echo "d /var/usrlocal 0755 root root - -" > /usr/lib/tmpfiles.d/macbook-local.conf && \
    echo "d /var/roothome 0700 root root - -" >> /usr/lib/tmpfiles.d/macbook-local.conf && \
    echo "d /var/data 0755 root root - -" >> /usr/lib/tmpfiles.d/macbook-local.conf && \
    # Sukuriame simbolinę nuorodą iš šaknies į /var vykdymo laiko duomenims
    ln -s /var/data /data

# 5.3 Bootc Native Kernel Arguments & Modprobe
RUN mkdir -p /usr/lib/bootc/kargs.d/ && \
    echo 'kargs = ["acpi_osi=!Darwin", "acpi_osi=!Windows 2012", "rhgb", "quiet"]' > /usr/lib/bootc/kargs.d/10-macbook.toml && \
    mkdir -p /usr/lib/modprobe.d/ && \
    echo 'options snd_hda_intel power_save=1' > /usr/lib/modprobe.d/audio-power-save.conf

# 5.4. Pasirinktiniai servisai ir konfigūracijos
COPY suspend-fix.service /usr/lib/systemd/system/suspend-fix.service
COPY powertop.service /usr/lib/systemd/system/powertop.service
COPY macbook.conf /usr/lib/modules-load.d/macbook.conf
COPY hid-apple.conf /usr/lib/modprobe.d/hid-apple.conf

# 5.5. Užtikriname Plymouth temą
RUN plymouth-set-default-theme -R spinner

# 5.6. Logind konfigūracija
RUN mkdir -p /usr/lib/systemd/logind.conf.d/
COPY 10-powerkey.conf /usr/lib/systemd/logind.conf.d/10-powerkey.conf

# 6. System Configuration & Services
RUN echo "facetimehd" > /usr/lib/modules-load.d/facetimehd.conf && \
    systemctl set-default graphical.target && \
    systemctl enable firewalld NetworkManager.service mbpfan.service suspend-fix.service powertop.service zram-swap.service sddm.service && \
    systemctl --global enable pipewire.service wireplumber.service

# 6.1. Maskuojame nereikalingus servisus bootc aplinkai
RUN systemctl mask systemd-remount-fs.service

# 7. Regenerate Initramfs
RUN kver="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')" && \
    dracut -vf "/usr/lib/modules/${kver}/initramfs.img" "${kver}"

# 8. Final cleanup ir tmpfiles.d generavimas
RUN <<CLEANUP
echo "▸ Final cleanup for bootc compliance"
dnf5 clean all
rm -rfv /boot/*
rm -rfv /run/* /run/.[!.]*
rm -rfv /tmp/* /tmp/.[!.]*
rm -rfv /var/cache/* \
        /var/log/* \
        /var/tmp/* \
        /var/cache/libdnf5/* \
        /var/lib/dnf
CLEANUP

# 9. Lint the final image
RUN bootc container lint
