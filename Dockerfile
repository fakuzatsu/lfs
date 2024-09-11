FROM debian:10-slim

SHELL ["/bin/bash", "-c"]

# image info
LABEL description="Automated LFS build"
LABEL version="8.2.1"
LABEL maintainer="fakuzatsu@gmail.com"

# Define build-time arguments with default values
# LFS mount point
ARG LFS=/mnt/lfs

# Other LFS parameters
ARG LC_ALL=POSIX
ARG LFS_TGT=x86_64-lfs-linux-gnu
ARG PATH=/tools/bin:/bin:/usr/bin:/sbin:/usr/sbin

# Defines how toolchain is fetched
# 0 use LFS wget file
# 1 use binaries from toolchain folder
# 2 use GitHub release artifacts
ARG FETCH_TOOLCHAIN_MODE=2

# Set 1 to run tests; running tests takes much more time
ARG LFS_TEST=0

# Set 1 to install documentation; slightly increases final size
ARG LFS_DOCS=0

# Degree of parallelism for compilation
ARG JOB_COUNT=1

# Initial RAM disk size in KB; must be in sync with CONFIG_BLK_DEV_RAM_SIZE
ARG IMAGE_SIZE=900000

# Location of initrd tree
ARG INITRD_TREE

# Output image
ARG IMAGE=isolinux/ramdisk.img

# Set environment variables using ARG values
ENV LFS=${LFS}
ENV LC_ALL=${LC_ALL}
ENV LFS_TGT=${LFS_TGT}
ENV PATH=${PATH}
ENV FETCH_TOOLCHAIN_MODE=${FETCH_TOOLCHAIN_MODE}
ENV LFS_TEST=${LFS_TEST}
ENV LFS_DOCS=${LFS_DOCS}
ENV JOB_COUNT=${JOB_COUNT}
# Define MAKEFLAGS with parallelism
ENV MAKEFLAGS="-j ${JOB_COUNT}"
ENV IMAGE_SIZE=${IMAGE_SIZE}
# Default to LFS if INITRD_TREE is not provided
ENV INITRD_TREE=${INITRD_TREE:-${LFS}}
ENV IMAGE=${IMAGE}

# Install required packages
RUN apt-get update && apt-get install -y \
    build-essential                      \
    bison                                \
    file                                 \
    gawk                                 \
    texinfo                              \
    wget                                 \
    sudo                                 \
    genisoimage                          \
    libelf-dev                           \
    bc                                   \
    libssl-dev                           \
 && apt-get -q -y autoremove             \
 && apt-get clean                        \
 && rm -rf /var/lib/apt/lists/*

# Create sources directory as writable and sticky
RUN mkdir -pv     $LFS/sources \
 && chmod -v a+wt $LFS/sources
WORKDIR $LFS/sources

# Create tools directory and symlink
RUN mkdir -pv $LFS/tools   \
 && ln    -sv $LFS/tools /

# Copy local binaries if present
COPY ["toolchain/", "$LFS/sources/"]

# Copy scripts
COPY [ "scripts/library-check.sh", \
       "scripts/version-check.sh", \
       "scripts/prepare/",         \
       "scripts/build/",           \
       "scripts/image/",           \
       "$LFS/tools/" ]

# Copy configuration
COPY [ "config/kernel.config", "$LFS/tools/" ]

# Check environment
RUN chmod +x $LFS/tools/*.sh    \
 && sync                        \
 && $LFS/tools/version-check.sh \
 && $LFS/tools/library-check.sh

# Create lfs user with 'lfs' password
RUN groupadd lfs                                    \
 && useradd -s /bin/bash -g lfs -m -k /dev/null lfs \
 && echo "lfs:lfs" | chpasswd \
 && adduser lfs sudo

# Give lfs user ownership of directories
RUN chown -v lfs $LFS/tools  \
 && chown -v lfs $LFS/sources

# Avoid sudo password
RUN echo "lfs ALL = NOPASSWD : ALL" >> /etc/sudoers \
 && echo 'Defaults env_keep += "LFS LC_ALL LFS_TGT PATH MAKEFLAGS FETCH_TOOLCHAIN_MODE LFS_TEST LFS_DOCS JOB_COUNT IMAGE_SIZE INITRD_TREE IMAGE"' >> /etc/sudoers

# Switch to lfs user and copy configuration files
USER lfs
COPY [ "config/.bash_profile", "config/.bashrc", "/home/lfs/" ]

# Ensure the bash profile is sourced correctly
RUN sudo chown lfs:lfs /home/lfs/.bashrc \
 && echo "source ~/.bash_profile" | sudo -u lfs tee -a /home/lfs/.bashrc > /dev/null

# Download the toolchain
RUN /tools/3.1-download-tools.sh

# Build the toolchain
RUN /tools/5.4-make-binutils.sh
RUN /tools/5.5-make-gcc.sh
RUN /tools/5.6-make-linux-api-headers.sh
RUN /tools/5.7-make-glibc.sh
RUN /tools/5.8-make-libstdc.sh
RUN /tools/5.9-make-binutils.sh
RUN /tools/5.10-make-gcc.sh
RUN /tools/5.11-make-tcl.sh
RUN /tools/5.12-make-expect.sh
RUN /tools/5.13-make-dejagnu.sh
RUN /tools/5.14-make-m4.sh
RUN /tools/5.15-make-ncurses.sh
RUN /tools/5.16-make-bash.sh
RUN /tools/5.17-make-bison.sh
RUN /tools/5.18-make-bzip2.sh
RUN /tools/5.19-make-coreutils.sh
RUN /tools/5.20-make-diffutils.sh
RUN /tools/5.21-make-file.sh
RUN /tools/5.22-make-findutils.sh
RUN /tools/5.23-make-gawk.sh
RUN /tools/5.24-make-gettext.sh
RUN /tools/5.25-make-grep.sh
RUN /tools/5.26-make-gzip.sh
RUN /tools/5.27-make-make.sh
RUN /tools/5.28-make-patch.sh
RUN /tools/5.29-make-perl.sh
RUN /tools/5.30-make-sed.sh
RUN /tools/5.31-make-tar.sh
RUN /tools/5.32-make-texinfo.sh
RUN /tools/5.33-make-util-linux.sh
RUN /tools/5.34-make-xz.sh
RUN /tools/5.35-strip.sh

# Switch to root for elevated build
USER root
RUN chown -R root:root $LFS/tools && sync

# Let the party begin
ENTRYPOINT [ "/tools/run-build.sh" ]

# After the build completes, search and copy the ISO file
RUN ISO_PATH=$(find / -name "*.iso" 2>/dev/null | head -n 1) && \
    if [ -n "$ISO_PATH" ]; then cp "$ISO_PATH" ${LFS}/lfs.iso; else echo "ISO not found!"; exit 1; fi