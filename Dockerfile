FROM debian:10-slim

# image info
LABEL description="Automated LFS build"
LABEL version="8.2"
LABEL maintainer="ilya.builuk@gmail.com"

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
ENV MAKEFLAGS="-j ${JOB_COUNT}" # Define MAKEFLAGS with parallelism
ENV IMAGE_SIZE=${IMAGE_SIZE}
ENV INITRD_TREE=${INITRD_TREE:-${LFS}}  # Default to LFS if INITRD_TREE is not provided
ENV IMAGE=${IMAGE}

# install required packages
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
 && rm -rf /var/lib/apt/lists/*

# create sources directory as writable and sticky
RUN mkdir -pv     $LFS/sources \
 && chmod -v a+wt $LFS/sources
WORKDIR $LFS/sources

# create tools directory and symlink
RUN mkdir -pv $LFS/tools   \
 && ln    -sv $LFS/tools /

# copy local binaries if present
COPY ["toolchain/", "$LFS/sources/"]

# copy scripts
COPY [ "scripts/run-all.sh",       \
       "scripts/library-check.sh", \
       "scripts/version-check.sh", \
       "scripts/prepare/",         \
       "scripts/build/",           \
       "scripts/image/",           \
       "$LFS/tools/" ]
# copy configuration
COPY [ "config/kernel.config", "$LFS/tools/" ]

# check environment
RUN chmod +x $LFS/tools/*.sh    \
 && sync                        \
 && $LFS/tools/version-check.sh \
 && $LFS/tools/library-check.sh

# create lfs user with 'lfs' password
RUN groupadd lfs                                    \
 && useradd -s /bin/bash -g lfs -m -k /dev/null lfs \
 && echo "lfs:lfs" | chpasswd
RUN adduser lfs sudo

# give lfs user ownership of directories
RUN chown -v lfs $LFS/tools  \
 && chown -v lfs $LFS/sources

# avoid sudo password
RUN echo "lfs ALL = NOPASSWD : ALL" >> /etc/sudoers
RUN echo 'Defaults env_keep += "LFS LC_ALL LFS_TGT PATH MAKEFLAGS FETCH_TOOLCHAIN_MODE LFS_TEST LFS_DOCS JOB_COUNT LOOP IMAGE_SIZE INITRD_TREE IMAGE"' >> /etc/sudoers

# login as lfs user
USER lfs
COPY [ "config/.bash_profile", "config/.bashrc", "/home/lfs/" ]
RUN source ~/.bash_profile

# let's the party begin
ENTRYPOINT [ "/tools/run-all.sh" ]
