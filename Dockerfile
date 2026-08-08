# syntax=docker/dockerfile:1.7

# bump: alpine /ALPINE_VERSION=alpine:([\d.]+)/ docker:alpine|^3
# bump: alpine link "Release notes" https://alpinelinux.org/posts/Alpine-$LATEST-released.html
ARG ALPINE_VERSION=alpine:3.20.3
FROM $ALPINE_VERSION AS base

# Alpine Package Keeper options
ARG APK_OPTS=""

RUN --mount=type=cache,target=/var/cache/apk \
  apk add --cache-dir /var/cache/apk --update-cache $APK_OPTS \
  coreutils \
  pkgconfig \
  wget \
  rust cargo cargo-c \
  openssl-dev openssl-libs-static \
  ca-certificates \
  bash \
  tar \
  build-base \
  autoconf automake \
  libtool \
  diffutils \
  cmake meson ninja \
  git \
  yasm nasm \
  texinfo \
  jq \
  zlib-dev zlib-static \
  bzip2-dev bzip2-static \
  libxml2-dev libxml2-static \
  expat-dev expat-static \
  fontconfig-dev fontconfig-static \
  freetype freetype-dev freetype-static \
  graphite2-static \
  tiff tiff-dev \
  libjpeg-turbo libjpeg-turbo-dev \
  libpng-dev libpng-static \
  giflib giflib-dev \
  fribidi-dev fribidi-static \
  brotli-dev brotli-static \
  soxr-dev soxr-static \
  tcl \
  numactl-dev \
  cunit cunit-dev \
  fftw-dev \
  libsamplerate-dev libsamplerate-static \
  snappy snappy-dev snappy-static \
  xxd \
  xz-dev xz-static \
  python3 py3-packaging \
  linux-headers \
  curl \
  libdrm-dev

# linux-headers need by rtmpdump
# python3 py3-packaging needed by glib

# -O3 makes sure we compile with optimization. setting CFLAGS/CXXFLAGS seems to override
# default automake cflags.
# -static-libgcc is needed to make gcc not include gcc_s as "as-needed" shared library which
# cmake will include as a implicit library.
# other options to get hardened build (same as ffmpeg hardened)
ARG CFLAGS="-O3 -static-libgcc -fno-strict-overflow -fstack-protector-all -fPIC"
ARG CXXFLAGS="-O3 -static-libgcc -fno-strict-overflow -fstack-protector-all -fPIC"
ARG LDFLAGS="-Wl,-z,relro,-z,now"

# retry dns and some http codes that might be transient errors
ARG WGET_OPTS="--tries=10 --timeout=60 --waitretry=5 --retry-connrefused --retry-on-host-error --retry-on-http-error=429,500,502,503"

# --no-same-owner as we don't care about uid/gid even if we run as root. fixes invalid gid/uid issue.
ARG TAR_OPTS="--no-same-owner --extract --file"

FROM base AS dep-vmaf

# before aom as libvmaf uses it
# bump: vmaf /VMAF_VERSION=([\d.]+)/ https://github.com/Netflix/vmaf.git|*
# bump: vmaf after ./hashupdate Dockerfile VMAF $LATEST
# bump: vmaf link "Release" https://github.com/Netflix/vmaf/releases/tag/v$LATEST
# bump: vmaf link "Source diff $CURRENT..$LATEST" https://github.com/Netflix/vmaf/compare/v$CURRENT..v$LATEST
ARG VMAF_VERSION=3.2.0
ARG VMAF_URL="https://github.com/Netflix/vmaf/archive/refs/tags/v$VMAF_VERSION.tar.gz"
ARG VMAF_SHA256=a28f93f3b4fa65601be324587072e32a6a704a304ba7b1aec9b70b3f709bc1dc
ADD --checksum=sha256:$VMAF_SHA256 $VMAF_URL /vmaf.tar.gz
RUN \
  tar $TAR_OPTS vmaf.tar.gz && cd vmaf-*/libvmaf && \
  meson setup build \
    -Dbuildtype=release \
    -Ddefault_library=static \
    -Dbuilt_in_models=true \
    -Denable_tests=false \
    -Denable_docs=false \
    -Denable_avx512=true \
    -Denable_float=true && \
  ninja -j$(nproc) -vC build install
# extra libs stdc++ is for vmaf https://github.com/Netflix/vmaf/issues/788
RUN sed -i 's/-lvmaf /-lvmaf -lstdc++ /' /usr/local/lib/pkgconfig/libvmaf.pc

FROM base AS dep-subtitle-svg

# own build as alpine glib links with libmount etc
# bump: glib /GLIB_VERSION=([\d.]+)/ https://gitlab.gnome.org/GNOME/glib.git|^2
# bump: glib after ./hashupdate Dockerfile GLIB $LATEST
# bump: glib link "NEWS" https://gitlab.gnome.org/GNOME/glib/-/blob/main/NEWS?ref_type=heads
ARG GLIB_VERSION=2.84.1
ARG GLIB_URL="https://download.gnome.org/sources/glib/2.84/glib-$GLIB_VERSION.tar.xz"
ARG GLIB_SHA256=2b4bc2ec49611a5fc35f86aca855f2ed0196e69e53092bab6bb73396bf30789a
ADD --checksum=sha256:$GLIB_SHA256 $GLIB_URL /glib.tar.xz
RUN \
  tar $TAR_OPTS glib.tar.xz && cd glib-* && \
  meson setup build \
    -Dbuildtype=release \
    -Ddefault_library=static \
    -Dlibmount=disabled && \
  ninja -j$(nproc) -vC build install

# bump: harfbuzz /LIBHARFBUZZ_VERSION=([\d.]+)/ https://github.com/harfbuzz/harfbuzz.git|*
# bump: harfbuzz after ./hashupdate Dockerfile LIBHARFBUZZ $LATEST
# bump: harfbuzz link "NEWS" https://github.com/harfbuzz/harfbuzz/blob/main/NEWS
ARG LIBHARFBUZZ_VERSION=14.3.0
ARG LIBHARFBUZZ_URL="https://github.com/harfbuzz/harfbuzz/releases/download/$LIBHARFBUZZ_VERSION/harfbuzz-$LIBHARFBUZZ_VERSION.tar.xz"
ARG LIBHARFBUZZ_SHA256=16070d77cfc4ba1f1e7327e83bf9b3f55898081cabdb94e56a33e04fc8874eae
ADD --checksum=sha256:$LIBHARFBUZZ_SHA256 $LIBHARFBUZZ_URL /harfbuzz.tar.xz
RUN \
  tar $TAR_OPTS harfbuzz.tar.xz && cd harfbuzz-* && \
  meson setup build \
    -Dbuildtype=release \
    -Ddefault_library=static && \
  ninja -j$(nproc) -vC build install

# bump: cairo /CAIRO_VERSION=([\d.]+)/ https://gitlab.freedesktop.org/cairo/cairo.git|^1
# bump: cairo after ./hashupdate Dockerfile CAIRO $LATEST
# bump: cairo link "NEWS" https://gitlab.freedesktop.org/cairo/cairo/-/blob/master/NEWS?ref_type=heads
ARG CAIRO_VERSION=1.18.4
ARG CAIRO_URL="https://cairographics.org/releases/cairo-$CAIRO_VERSION.tar.xz"
ARG CAIRO_SHA256=445ed8208a6e4823de1226a74ca319d3600e83f6369f99b14265006599c32ccb
ADD --checksum=sha256:$CAIRO_SHA256 $CAIRO_URL /cairo.tar.xz
RUN \
  tar $TAR_OPTS cairo.tar.xz && cd cairo-* && \
  meson setup build \
    -Dbuildtype=release \
    -Ddefault_library=static \
    -Dtests=disabled \
    -Dquartz=disabled \
    -Dxcb=disabled \
    -Dxlib=disabled \
    -Dxlib-xcb=disabled && \
  ninja -j$(nproc) -vC build install

# TODO: there is weird "1.90" tag, skip it
# bump: pango /PANGO_VERSION=([\d.]+)/ https://github.com/GNOME/pango.git|/\d+\.\d+\.\d+/|*
# bump: pango after ./hashupdate Dockerfile PANGO $LATEST
# bump: pango link "NEWS" https://gitlab.gnome.org/GNOME/pango/-/blob/main/NEWS?ref_type=heads
ARG PANGO_VERSION=1.56.4
ARG PANGO_URL="https://download.gnome.org/sources/pango/1.56/pango-$PANGO_VERSION.tar.xz"
ARG PANGO_SHA256=17065e2fcc5f5a5bdbffc884c956bfc7c451a96e8c4fb2f8ad837c6413cb5a01
ADD --checksum=sha256:$PANGO_SHA256 $PANGO_URL /pango.tar.xz
# TODO: add -Dbuild-testsuite=false when in stable release
# TODO: -Ddefault_library=both currently to not fail building tests
RUN \
  tar $TAR_OPTS pango.tar.xz && cd pango-* && \
  meson setup build \
    -Dbuildtype=release \
    -Ddefault_library=both \
    -Dintrospection=disabled \
    -Dgtk_doc=false && \
  ninja -j$(nproc) -vC build install

# bump: librsvg /LIBRSVG_VERSION=([\d.]+)/ https://gitlab.gnome.org/GNOME/librsvg.git|^2
# bump: librsvg after ./hashupdate Dockerfile LIBRSVG $LATEST
# bump: librsvg link "NEWS" https://gitlab.gnome.org/GNOME/librsvg/-/blob/master/NEWS
ARG LIBRSVG_VERSION=2.60.0
ARG LIBRSVG_URL="https://download.gnome.org/sources/librsvg/2.60/librsvg-$LIBRSVG_VERSION.tar.xz"
ARG LIBRSVG_SHA256=0b6ffccdf6e70afc9876882f5d2ce9ffcf2c713cbaaf1ad90170daa752e1eec3
ADD --checksum=sha256:$LIBRSVG_SHA256 $LIBRSVG_URL /librsvg.tar.xz
RUN \
  tar $TAR_OPTS librsvg.tar.xz && cd librsvg-* && \
  # workaround for https://gitlab.gnome.org/GNOME/librsvg/-/issues/1158
  sed -i "/^if host_system in \['windows'/s/, 'linux'//" meson.build && \
  meson setup build \
    -Dbuildtype=release \
    -Ddefault_library=static \
    -Ddocs=disabled \
    -Dintrospection=disabled \
    -Dpixbuf=disabled \
    -Dpixbuf-loader=disabled \
    -Dvala=disabled \
    -Dtests=false && \
  ninja -j$(nproc) -vC build install

FROM base AS dep-aom
COPY --from=dep-vmaf /usr/local/ /usr/local/

# build after libvmaf
# bump: aom /AOM_VERSION=([\d.]+)/ git:https://aomedia.googlesource.com/aom|*
# bump: aom after ./hashupdate Dockerfile AOM $LATEST
# bump: aom after COMMIT=$(git ls-remote https://aomedia.googlesource.com/aom v$LATEST^{} | awk '{print $1}') && sed -i -E "s/^ARG AOM_COMMIT=.*/ARG AOM_COMMIT=$COMMIT/" Dockerfile
# bump: aom link "CHANGELOG" https://aomedia.googlesource.com/aom/+/refs/tags/v$LATEST/CHANGELOG
ARG AOM_VERSION=3.14.1
ARG AOM_URL="https://aomedia.googlesource.com/aom"
ARG AOM_COMMIT=03087864cf4bea6abb0d28f95cf7843511413d8f
RUN git clone --depth 1 --branch v$AOM_VERSION "$AOM_URL"
RUN cd aom && test $(git rev-parse HEAD) = $AOM_COMMIT
RUN \
  cd aom && \
  mkdir build_tmp && cd build_tmp && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DENABLE_EXAMPLES=NO \
    -DENABLE_DOCS=NO \
    -DENABLE_TESTS=NO \
    -DENABLE_TOOLS=NO \
    -DCONFIG_TUNE_VMAF=1 \
    -DENABLE_NASM=ON \
    -DCMAKE_INSTALL_LIBDIR=lib \
    .. && \
  make -j$(nproc) install

FROM dep-subtitle-svg AS dep-subtitle

# bump: libaribb24 /LIBARIBB24_VERSION=([\d.]+)/ https://github.com/nkoriyama/aribb24.git|*
# bump: libaribb24 after ./hashupdate Dockerfile LIBARIBB24 $LATEST
# bump: libaribb24 link "Release notes" https://github.com/nkoriyama/aribb24/releases/tag/$LATEST
ARG LIBARIBB24_VERSION=1.0.3
ARG LIBARIBB24_URL="https://github.com/nkoriyama/aribb24/archive/v$LIBARIBB24_VERSION.tar.gz"
ARG LIBARIBB24_SHA256=f61560738926e57f9173510389634d8c06cabedfa857db4b28fb7704707ff128
ADD --checksum=sha256:$LIBARIBB24_SHA256 $LIBARIBB24_URL /libaribb24.tar.gz
RUN \
  mkdir libaribb24 && \
  tar $TAR_OPTS libaribb24.tar.gz -C libaribb24 --strip-components=1 && cd libaribb24 && \
  autoreconf -fiv && \
  ./configure \
    --enable-static \
    --disable-shared && \
  make -j$(nproc) && make install

# bump: libass /LIBASS_VERSION=([\d.]+)/ https://github.com/libass/libass.git|*
# bump: libass after ./hashupdate Dockerfile LIBASS $LATEST
# bump: libass link "Release notes" https://github.com/libass/libass/releases/tag/$LATEST
ARG LIBASS_VERSION=0.17.5
ARG LIBASS_URL="https://github.com/libass/libass/releases/download/$LIBASS_VERSION/libass-$LIBASS_VERSION.tar.gz"
ARG LIBASS_SHA256=caab4b993dd7be6187c55623b789ed75dddefea6e65938af134637c732fe094a
ADD --checksum=sha256:$LIBASS_SHA256 $LIBASS_URL /libass.tar.gz
RUN \
  tar $TAR_OPTS libass.tar.gz && cd libass-* && \
  ./configure \
    --disable-shared \
    --enable-static && \
  make -j$(nproc) && make install

FROM base AS dep-bluray

# bump: libbluray /LIBBLURAY_VERSION=([\d.]+)/ https://code.videolan.org/videolan/libbluray.git|*
# bump: libbluray after ./hashupdate Dockerfile LIBBLURAY $LATEST
# bump: libbluray link "ChangeLog" https://code.videolan.org/videolan/libbluray/-/blob/master/ChangeLog
ARG LIBBLURAY_VERSION=1.5.0
ARG LIBBLURAY_URL="https://code.videolan.org/videolan/libbluray/-/archive/$LIBBLURAY_VERSION/libbluray-$LIBBLURAY_VERSION.tar.gz"
ARG LIBBLURAY_SHA256=7a5d945a9c2b0064a748b77a4c5ab563175bb7219e9d562b2b2399790726a388
ADD --checksum=sha256:$LIBBLURAY_SHA256 $LIBBLURAY_URL /libbluray.tar.gz
# TODO: bump config? at least checkout to make commit sticky
ARG LIBUDFREAD_COMMIT=c3cd5cbb097924557ea4d9da1ff76a74620c51a8
RUN \
  tar $TAR_OPTS libbluray.tar.gz && cd libbluray-* && \
  git clone https://code.videolan.org/videolan/libudfread.git contrib/libudfread && \
  (cd contrib/libudfread && git checkout --recurse-submodules $LIBUDFREAD_COMMIT) && \
  meson setup build \
    -Dbuildtype=release \
    -Ddefault_library=static && \
  ninja -j$(nproc) -vC build install

FROM base AS dep-dav1d

# bump: dav1d /DAV1D_VERSION=([\d.]+)/ https://code.videolan.org/videolan/dav1d.git|*
# bump: dav1d after ./hashupdate Dockerfile DAV1D $LATEST
# bump: dav1d link "Release notes" https://code.videolan.org/videolan/dav1d/-/tags/$LATEST
ARG DAV1D_VERSION=1.5.4
ARG DAV1D_URL="https://code.videolan.org/videolan/dav1d/-/archive/$DAV1D_VERSION/dav1d-$DAV1D_VERSION.tar.gz"
ARG DAV1D_SHA256=a1d5b63d2d38ec9bd03acf643caa51fa22edd1e89c5a109c4807717216bbec07
ADD --checksum=sha256:$DAV1D_SHA256 $DAV1D_URL /dav1d.tar.gz
RUN \
  tar $TAR_OPTS dav1d.tar.gz && cd dav1d-* && \
  meson setup build \
    -Dbuildtype=release \
    -Ddefault_library=static && \
  ninja -j$(nproc) -vC build install

FROM base AS dep-fdkaac

# bump: fdk-aac /FDK_AAC_VERSION=([\d.]+)/ https://github.com/mstorsjo/fdk-aac.git|*
# bump: fdk-aac after ./hashupdate Dockerfile FDK_AAC $LATEST
# bump: fdk-aac link "ChangeLog" https://github.com/mstorsjo/fdk-aac/blob/master/ChangeLog
# bump: fdk-aac link "Source diff $CURRENT..$LATEST" https://github.com/mstorsjo/fdk-aac/compare/v$CURRENT..v$LATEST
ARG FDK_AAC_VERSION=2.0.3
ARG FDK_AAC_URL="https://github.com/mstorsjo/fdk-aac/archive/v$FDK_AAC_VERSION.tar.gz"
ARG FDK_AAC_SHA256=e25671cd96b10bad896aa42ab91a695a9e573395262baed4e4a2ff178d6a3a78
ADD --checksum=sha256:$FDK_AAC_SHA256 $FDK_AAC_URL /fdk-aac.tar.gz
RUN \
  tar $TAR_OPTS fdk-aac.tar.gz && cd fdk-aac-* && \
  ./autogen.sh && \
  ./configure \
    --disable-shared \
    --enable-static && \
  make -j$(nproc) install

FROM base AS dep-audio-mp3

# bump: mp3lame /MP3LAME_VERSION=([\d.]+)/ svn:http://svn.code.sf.net/p/lame/svn|/^RELEASE__(.*)$/|/_/./|*
# bump: mp3lame after ./hashupdate Dockerfile MP3LAME $LATEST
# bump: mp3lame link "ChangeLog" http://svn.code.sf.net/p/lame/svn/trunk/lame/ChangeLog
ARG MP3LAME_VERSION=3.100
ARG MP3LAME_URL="https://sourceforge.net/projects/lame/files/lame/$MP3LAME_VERSION/lame-$MP3LAME_VERSION.tar.gz/download"
ARG MP3LAME_SHA256=ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e
ADD --checksum=sha256:$MP3LAME_SHA256 $MP3LAME_URL /lame.tar.gz
RUN \
  tar $TAR_OPTS lame.tar.gz && cd lame-* && \
  ./configure \
    --disable-shared \
    --enable-static \
    --enable-nasm \
    --disable-gtktest \
    --disable-cpml \
    --disable-frontend && \
  make -j$(nproc) install

FROM base AS dep-filter-core

# bump: lcms2 /LCMS2_VERSION=([\d.]+)/ https://github.com/mm2/Little-CMS.git|^2
# bump: lcms2 after ./hashupdate Dockerfile LCMS2 $LATEST
# bump: lcms2 link "Release" https://github.com/mm2/Little-CMS/releases/tag/lcms$LATEST
ARG LCMS2_VERSION=2.19.1
ARG LCMS2_URL="https://github.com/mm2/Little-CMS/releases/download/lcms$LCMS2_VERSION/lcms2-$LCMS2_VERSION.tar.gz"
ARG LCMS2_SHA256=bfc54f7bab59fbc921012014a8032e4cba4abd46db47d46b76416a8c0b2815c8
ADD --checksum=sha256:$LCMS2_SHA256 $LCMS2_URL /lcms2.tar.gz
RUN \
  tar $TAR_OPTS lcms2.tar.gz && cd lcms2-* && \
  ./autogen.sh && \
  ./configure \
    --enable-static \
    --disable-shared && \
  make -j$(nproc) install

# bump: libmysofa /LIBMYSOFA_VERSION=([\d.]+)/ https://github.com/hoene/libmysofa.git|^1
# bump: libmysofa after ./hashupdate Dockerfile LIBMYSOFA $LATEST
# bump: libmysofa link "Release" https://github.com/hoene/libmysofa/releases/tag/v$LATEST
# bump: libmysofa link "Source diff $CURRENT..$LATEST" https://github.com/hoene/libmysofa/compare/v$CURRENT..v$LATEST
ARG LIBMYSOFA_VERSION=1.3.5
ARG LIBMYSOFA_URL="https://github.com/hoene/libmysofa/archive/refs/tags/v$LIBMYSOFA_VERSION.tar.gz"
ARG LIBMYSOFA_SHA256=f29508c335c83d8703f943ffc9ca783ac39aca84e851357f13a55af0f8143137
ADD --checksum=sha256:$LIBMYSOFA_SHA256 $LIBMYSOFA_URL /libmysofa.tar.gz
RUN \
  tar $TAR_OPTS libmysofa.tar.gz && cd libmysofa-*/build && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TESTS=OFF \
    .. && \
  make -j$(nproc) install

FROM base AS dep-image

# bump: openjpeg /OPENJPEG_VERSION=([\d.]+)/ https://github.com/uclouvain/openjpeg.git|*
# bump: openjpeg after ./hashupdate Dockerfile OPENJPEG $LATEST
# bump: openjpeg link "CHANGELOG" https://github.com/uclouvain/openjpeg/blob/master/CHANGELOG.md
ARG OPENJPEG_VERSION=2.5.4
ARG OPENJPEG_URL="https://github.com/uclouvain/openjpeg/archive/v$OPENJPEG_VERSION.tar.gz"
ARG OPENJPEG_SHA256=a695fbe19c0165f295a8531b1e4e855cd94d0875d2f88ec4b61080677e27188a
ADD --checksum=sha256:$OPENJPEG_SHA256 $OPENJPEG_URL /openjpeg.tar.gz
RUN \
  tar $TAR_OPTS openjpeg.tar.gz && cd openjpeg-* && \
  mkdir build && cd build && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_PKGCONFIG_FILES=ON \
    -DBUILD_CODEC=OFF \
    -DWITH_ASTYLE=OFF \
    -DBUILD_TESTING=OFF \
    .. && \
  make -j$(nproc) install

FROM base AS dep-audio-opus

# bump: opus /OPUS_VERSION=([\d.]+)/ https://github.com/xiph/opus.git|^1
# bump: opus after ./hashupdate Dockerfile OPUS $LATEST
# bump: opus link "Release notes" https://github.com/xiph/opus/releases/tag/v$LATEST
# bump: opus link "Source diff $CURRENT..$LATEST" https://github.com/xiph/opus/compare/v$CURRENT..v$LATEST
ARG OPUS_VERSION=1.6.1
ARG OPUS_URL="https://downloads.xiph.org/releases/opus/opus-$OPUS_VERSION.tar.gz"
ARG OPUS_SHA256=6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1
ADD --checksum=sha256:$OPUS_SHA256 $OPUS_URL /opus.tar.gz
RUN \
  tar $TAR_OPTS opus.tar.gz && cd opus-* && \
  ./configure \
    --disable-shared \
    --enable-static \
    --disable-extra-programs \
    --disable-doc && \
  make -j$(nproc) install

FROM base AS dep-rabbitmq

# bump: librabbitmq /LIBRABBITMQ_VERSION=([\d.]+)/ https://github.com/alanxz/rabbitmq-c.git|*
# bump: librabbitmq after ./hashupdate Dockerfile LIBRABBITMQ $LATEST
# bump: librabbitmq link "ChangeLog" https://github.com/alanxz/rabbitmq-c/blob/master/ChangeLog.md
ARG LIBRABBITMQ_VERSION=0.17.0
ARG LIBRABBITMQ_URL="https://github.com/alanxz/rabbitmq-c/archive/refs/tags/v$LIBRABBITMQ_VERSION.tar.gz"
ARG LIBRABBITMQ_SHA256=66c36901178c872565f732468e91688f6280c18810fe8b21a199d46347ba3a0c
ADD --checksum=sha256:$LIBRABBITMQ_SHA256 $LIBRABBITMQ_URL /rabbitmq-c.tar.gz
RUN \
  tar $TAR_OPTS rabbitmq-c.tar.gz && cd rabbitmq-c-* && \
  mkdir build && cd build && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_STATIC_LIBS=ON \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TESTS=OFF \
    -DBUILD_TOOLS=OFF \
    -DBUILD_TOOLS_DOCS=OFF \
    -DRUN_SYSTEM_TESTS=OFF \
    .. && \
  make -j$(nproc) install

FROM base AS dep-rav1e

# bump: rav1e /RAV1E_VERSION=([\d.]+)/ https://github.com/xiph/rav1e.git|/\d+\./|*
# bump: rav1e after ./hashupdate Dockerfile RAV1E $LATEST
# bump: rav1e link "Release notes" https://github.com/xiph/rav1e/releases/tag/v$LATEST
ARG RAV1E_VERSION=0.7.1
ARG RAV1E_URL="https://github.com/xiph/rav1e/archive/v$RAV1E_VERSION.tar.gz"
ARG RAV1E_SHA256=da7ae0df2b608e539de5d443c096e109442cdfa6c5e9b4014361211cf61d030c
ADD --checksum=sha256:$RAV1E_SHA256 $RAV1E_URL /rav1e.tar.gz
RUN --mount=type=cache,target=/root/.cargo/registry \
  --mount=type=cache,target=/root/.cargo/git \
  tar $TAR_OPTS rav1e.tar.gz && cd rav1e-* && \
  RUSTFLAGS="-C target-feature=+crt-static" \
  cargo cinstall --release

FROM base AS dep-network-core

# bump: librtmp /LIBRTMP_COMMIT=([[:xdigit:]]+)/ gitrefs:https://git.ffmpeg.org/rtmpdump.git|re:#^refs/heads/master$#|@commit
# bump: librtmp after ./hashupdate Dockerfile LIBRTMP $LATEST
# bump: librtmp link "Commit diff $CURRENT..$LATEST" https://git.ffmpeg.org/gitweb/rtmpdump.git/commitdiff/$LATEST?ds=sidebyside
ARG LIBRTMP_URL="https://git.ffmpeg.org/rtmpdump.git"
ARG LIBRTMP_COMMIT=138fdb258d9fc26f1843fd1b891180416c9dc575
RUN \
  git clone "$LIBRTMP_URL" && cd rtmpdump && \
  git checkout --recurse-submodules $LIBRTMP_COMMIT && \
  make SYS=posix SHARED=off -j$(nproc) install

FROM base AS dep-filter-extra

# bump: rubberband /RUBBERBAND_VERSION=([\d.]+)/ https://github.com/breakfastquay/rubberband.git|^2
# bump: rubberband after ./hashupdate Dockerfile RUBBERBAND $LATEST
# bump: rubberband link "CHANGELOG" https://github.com/breakfastquay/rubberband/blob/default/CHANGELOG
# bump: rubberband link "Source diff $CURRENT..$LATEST" https://github.com/breakfastquay/rubberband/compare/$CURRENT..$LATEST
ARG RUBBERBAND_VERSION=2.0.2
ARG RUBBERBAND_URL="https://breakfastquay.com/files/releases/rubberband-$RUBBERBAND_VERSION.tar.bz2"
ARG RUBBERBAND_SHA256=b9eac027e797789ae99611c9eaeaf1c3a44cc804f9c8a0441a0d1d26f3d6bdf9
ADD --checksum=sha256:$RUBBERBAND_SHA256 $RUBBERBAND_URL /rubberband.tar.bz2
RUN \
  tar $TAR_OPTS rubberband.tar.bz2 && cd rubberband-* && \
  meson setup build \
    -Ddefault_library=static \
    -Dfft=fftw \
    -Dresampler=libsamplerate && \
  ninja -j$(nproc) -vC build install && \
  echo "Requires.private: fftw3 samplerate" >> /usr/local/lib/pkgconfig/rubberband.pc

FROM base AS dep-network-secure

# bump: srt /SRT_VERSION=([\d.]+)/ https://github.com/Haivision/srt.git|^1
# bump: srt after ./hashupdate Dockerfile SRT $LATEST
# bump: srt link "Release notes" https://github.com/Haivision/srt/releases/tag/v$LATEST
ARG SRT_VERSION=1.5.6
ARG SRT_URL="https://github.com/Haivision/srt/archive/v$SRT_VERSION.tar.gz"
ARG SRT_SHA256=2c4980c2c4cfd142d21b829d939dc51db9c6628af5967fff62fd7290769569c7
ADD --checksum=sha256:$SRT_SHA256 $SRT_URL /libsrt.tar.gz
RUN \
  tar $TAR_OPTS libsrt.tar.gz && cd srt-* && \
  mkdir build && cd build && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_SHARED=OFF \
    -DENABLE_APPS=OFF \
    -DENABLE_CXX11=ON \
    -DUSE_STATIC_LIBSTDCXX=ON \
    -DOPENSSL_USE_STATIC_LIBS=ON \
    -DENABLE_LOGGING=OFF \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_INSTALL_INCLUDEDIR=include \
    -DCMAKE_INSTALL_BINDIR=bin \
    .. && \
  make -j$(nproc) && make install

# bump: libssh /LIBSSH_VERSION=([\d.]+)/ https://gitlab.com/libssh/libssh-mirror.git|*
# bump: libssh after ./hashupdate Dockerfile LIBSSH $LATEST
# bump: libssh link "Source diff $CURRENT..$LATEST" https://gitlab.com/libssh/libssh-mirror/-/compare/libssh-$CURRENT...libssh-$LATEST
# bump: libssh link "Release notes" https://gitlab.com/libssh/libssh-mirror/-/tags/libssh-$LATEST
ARG LIBSSH_VERSION=0.12.1
ARG LIBSSH_URL="https://gitlab.com/libssh/libssh-mirror/-/archive/libssh-$LIBSSH_VERSION/libssh-mirror-libssh-$LIBSSH_VERSION.tar.gz"
ARG LIBSSH_SHA256=8c45cb01fbd373334561fd6d1bbe124cdc6ef541c17fc17dee10747ce2d6433f
ADD --checksum=sha256:$LIBSSH_SHA256 $LIBSSH_URL /libssh.tar.gz
# LIBSSH_STATIC=1 is REQUIRED to link statically against libssh.a so add to pkg-config file
RUN \
  tar $TAR_OPTS libssh.tar.gz && cd libssh* && \
  mkdir build && cd build && \
  echo -e 'Requires.private: libssl libcrypto zlib \nLibs.private: -DLIBSSH_STATIC=1 -lssh\nCflags.private: -DLIBSSH_STATIC=1 -I${CMAKE_INSTALL_FULL_INCLUDEDIR}' >> ../libssh.pc.cmake && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_SYSTEM_ARCH=$(arch) \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_BUILD_TYPE=Release \
    -DPICKY_DEVELOPER=ON \
    -DBUILD_STATIC_LIB=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DWITH_GSSAPI=OFF \
    -DWITH_BLOWFISH_CIPHER=ON \
    -DWITH_SFTP=ON \
    -DWITH_SERVER=OFF \
    -DWITH_ZLIB=ON \
    -DWITH_PCAP=ON \
    -DWITH_DEBUG_CRYPTO=OFF \
    -DWITH_DEBUG_PACKET=OFF \
    -DWITH_DEBUG_CALLTRACE=OFF \
    -DUNIT_TESTING=OFF \
    -DCLIENT_TESTING=OFF \
    -DSERVER_TESTING=OFF \
    -DWITH_EXAMPLES=OFF \
    -DWITH_INTERNAL_DOC=OFF \
    .. && \
  # make -j seems to be shaky, libssh.a ends up truncated (used before fully created?)
  make install

FROM base AS dep-svtav1

# bump: svtav1 /SVTAV1_VERSION=([\d.]+)/ https://gitlab.com/AOMediaCodec/SVT-AV1.git|*
# bump: svtav1 after ./hashupdate Dockerfile SVTAV1 $LATEST
# bump: svtav1 link "Release notes" https://gitlab.com/AOMediaCodec/SVT-AV1/-/releases/v$LATEST
ARG SVTAV1_VERSION=4.2.0
ARG SVTAV1_URL="https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v$SVTAV1_VERSION/SVT-AV1-v$SVTAV1_VERSION.tar.bz2"
ARG SVTAV1_SHA256=512f2ea5649e3e76c2dddcc25c2556fb67a9582baaab207c9c96161c94659dad
ADD --checksum=sha256:$SVTAV1_SHA256 $SVTAV1_URL /svtav1.tar.bz2
RUN \
  tar $TAR_OPTS svtav1.tar.bz2 && cd SVT-AV1-*/Build && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DBUILD_SHARED_LIBS=OFF \
    -DENABLE_AVX512=ON \
    -DCMAKE_BUILD_TYPE=Release \
    .. && \
  make -j$(nproc) install

FROM base AS dep-audio-ogg

# has to be before theora
# bump: ogg /OGG_VERSION=([\d.]+)/ https://github.com/xiph/ogg.git|*
# bump: ogg after ./hashupdate Dockerfile OGG $LATEST
# bump: ogg link "CHANGES" https://github.com/xiph/ogg/blob/master/CHANGES
# bump: ogg link "Source diff $CURRENT..$LATEST" https://github.com/xiph/ogg/compare/v$CURRENT..v$LATEST
ARG OGG_VERSION=1.3.6
ARG OGG_URL="https://downloads.xiph.org/releases/ogg/libogg-$OGG_VERSION.tar.gz"
ARG OGG_SHA256=83e6704730683d004d20e21b8f7f55dcb3383cdf84c0daedf30bde175f774638
ADD --checksum=sha256:$OGG_SHA256 $OGG_URL /libogg.tar.gz
RUN \
  tar $TAR_OPTS libogg.tar.gz && cd libogg-* && \
  ./configure \
    --disable-shared \
    --enable-static && \
  make -j$(nproc) install

FROM base AS dep-vidstab

# bump: vid.stab /VIDSTAB_VERSION=([\d.]+)/ https://github.com/georgmartius/vid.stab.git|*
# bump: vid.stab after ./hashupdate Dockerfile VIDSTAB $LATEST
# bump: vid.stab link "Changelog" https://github.com/georgmartius/vid.stab/blob/master/Changelog
ARG VIDSTAB_VERSION=1.1.2
ARG VIDSTAB_URL="https://github.com/georgmartius/vid.stab/archive/v$VIDSTAB_VERSION.tar.gz"
ARG VIDSTAB_SHA256=96db34d48a9e3aa13736a48744b56dfb76731ac9bb5193c716de8534c9fd709d
ADD --checksum=sha256:$VIDSTAB_SHA256 $VIDSTAB_URL /vid.stab.tar.gz
RUN \
  tar $TAR_OPTS vid.stab.tar.gz && cd vid.stab-* && \
  mkdir build && cd build && \
  # This line workarounds the issue that happens when the image builds in emulated (buildx) arm64 environment.
  # Since in emulated container the /proc is mounted from the host, the cmake not able to detect CPU features correctly.
  sed -i 's/include (FindSSE)/if(CMAKE_SYSTEM_ARCH MATCHES "amd64")\ninclude (FindSSE)\nendif()/' ../CMakeLists.txt && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_SYSTEM_ARCH=$(arch) \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DUSE_OMP=ON \
    .. && \
  make -j$(nproc) install
RUN echo "Libs.private: -ldl" >> /usr/local/lib/pkgconfig/vidstab.pc

FROM dep-audio-ogg AS dep-audio-vorbis

# bump: vorbis /VORBIS_VERSION=([\d.]+)/ https://github.com/xiph/vorbis.git|*
# bump: vorbis after ./hashupdate Dockerfile VORBIS $LATEST
# bump: vorbis link "CHANGES" https://github.com/xiph/vorbis/blob/master/CHANGES
# bump: vorbis link "Source diff $CURRENT..$LATEST" https://github.com/xiph/vorbis/compare/v$CURRENT..v$LATEST
ARG VORBIS_VERSION=1.3.7
ARG VORBIS_URL="https://downloads.xiph.org/releases/vorbis/libvorbis-$VORBIS_VERSION.tar.gz"
ARG VORBIS_SHA256=0e982409a9c3fc82ee06e08205b1355e5c6aa4c36bca58146ef399621b0ce5ab
ADD --checksum=sha256:$VORBIS_SHA256 $VORBIS_URL /libvorbis.tar.gz
RUN \
  tar $TAR_OPTS libvorbis.tar.gz && cd libvorbis-* && \
  ./configure \
    --disable-shared \
    --enable-static \
    --disable-oggtest && \
  make -j$(nproc) install

FROM base AS dep-video-modern

# bump: libvpx /VPX_VERSION=([\d.]+)/ https://github.com/webmproject/libvpx.git|*
# bump: libvpx after ./hashupdate Dockerfile VPX $LATEST
# bump: libvpx link "CHANGELOG" https://github.com/webmproject/libvpx/blob/master/CHANGELOG
# bump: libvpx link "Source diff $CURRENT..$LATEST" https://github.com/webmproject/libvpx/compare/v$CURRENT..v$LATEST
ARG VPX_VERSION=1.16.0
ARG VPX_URL="https://github.com/webmproject/libvpx/archive/v$VPX_VERSION.tar.gz"
ARG VPX_SHA256=7a479a3c66b9f5d5542a4c6a1b7d3768a983b1e5c14c60a9396edc9b649e015c
ADD --checksum=sha256:$VPX_SHA256 $VPX_URL /libvpx.tar.gz
RUN \
  tar $TAR_OPTS libvpx.tar.gz && cd libvpx-* && \
  ./configure \
    --enable-static \
    --enable-vp9-highbitdepth \
    --disable-shared \
    --disable-unit-tests \
    --disable-examples && \
  make -j$(nproc) install

# bump: libwebp /LIBWEBP_VERSION=([\d.]+)/ https://github.com/webmproject/libwebp.git|^1
# bump: libwebp after ./hashupdate Dockerfile LIBWEBP $LATEST
# bump: libwebp link "Release notes" https://github.com/webmproject/libwebp/releases/tag/v$LATEST
# bump: libwebp link "Source diff $CURRENT..$LATEST" https://github.com/webmproject/libwebp/compare/v$CURRENT..v$LATEST
ARG LIBWEBP_VERSION=1.6.0
ARG LIBWEBP_URL="https://github.com/webmproject/libwebp/archive/v$LIBWEBP_VERSION.tar.gz"
ARG LIBWEBP_SHA256=93a852c2b3efafee3723efd4636de855b46f9fe1efddd607e1f42f60fc8f2136
ADD --checksum=sha256:$LIBWEBP_SHA256 $LIBWEBP_URL /libwebp.tar.gz
RUN \
  tar $TAR_OPTS libwebp.tar.gz && cd libwebp-* && \
  ./autogen.sh && \
  ./configure \
    --disable-shared \
    --enable-static \
    --with-pic \
    --enable-libwebpmux \
    --disable-libwebpextras \
    --disable-libwebpdemux \
    --disable-sdl \
    --disable-gl \
    --disable-png \
    --disable-jpeg \
    --disable-tiff \
    --disable-gif && \
  make -j$(nproc) install

# x264 only have a stable branch no tags and we checkout commit so no hash is needed
# bump: x264 /X264_VERSION=([[:xdigit:]]+)/ gitrefs:https://code.videolan.org/videolan/x264.git|re:#^refs/heads/stable$#|@commit
# bump: x264 after ./hashupdate Dockerfile X264 $LATEST
# bump: x264 link "Source diff $CURRENT..$LATEST" https://code.videolan.org/videolan/x264/-/compare/$CURRENT...$LATEST
ARG X264_URL="https://code.videolan.org/videolan/x264.git"
ARG X264_VERSION=b35605ace3ddf7c1a5d67a2eb553f034aef41d55
RUN \
  git clone "$X264_URL" && cd x264 && \
  git checkout --recurse-submodules $X264_VERSION && \
  ./configure \
    --enable-pic \
    --enable-static \
    --disable-cli \
    --disable-lavf \
    --disable-swscale && \
  make -j$(nproc) install

# bump: x265 /X265_VERSION=([\d.]+)/ https://bitbucket.org/multicoreware/x265_git.git|*
# bump: x265 after ./hashupdate Dockerfile X265 $LATEST
# bump: x265 link "Source diff $CURRENT..$LATEST" https://bitbucket.org/multicoreware/x265_git/branches/compare/$LATEST..$CURRENT#diff
ARG X265_VERSION=4.2
ARG X265_SHA256=40b1ea0453e0309f0eba934e0ddf533f8f6295966679e8894e8f1c1c8d5e1210
ARG X265_URL="https://bitbucket.org/multicoreware/x265_git/downloads/x265_$X265_VERSION.tar.gz"
ADD --checksum=sha256:$X265_SHA256 $X265_URL /x265_git.tar.bz2
# CMAKEFLAGS issue
# https://bitbucket.org/multicoreware/x265_git/issues/620/support-passing-cmake-flags-to-multilibsh
RUN \
  tar $TAR_OPTS x265_git.tar.bz2 && cd x265_*/build/linux && \
  sed -i '/^cmake / s/$/ -G "Unix Makefiles" ${CMAKEFLAGS}/' ./multilib.sh && \
  sed -i 's/ -DENABLE_SHARED=OFF//g' ./multilib.sh && \
  MAKEFLAGS="-j$(nproc)" \
  CMAKEFLAGS="-DENABLE_SHARED=OFF -DCMAKE_VERBOSE_MAKEFILE=ON -DENABLE_AGGRESSIVE_CHECKS=ON -DENABLE_NASM=ON -DCMAKE_BUILD_TYPE=Release" \
  ./multilib.sh && \
  make -C 8bit -j$(nproc) install

FROM base AS dep-zimg

# bump: zimg /ZIMG_VERSION=([\d.]+)/ https://github.com/sekrit-twc/zimg.git|*
# bump: zimg after ./hashupdate Dockerfile ZIMG $LATEST
# bump: zimg link "ChangeLog" https://github.com/sekrit-twc/zimg/blob/master/ChangeLog
ARG ZIMG_VERSION=3.0.6
ARG ZIMG_URL="https://github.com/sekrit-twc/zimg/archive/release-$ZIMG_VERSION.tar.gz"
ARG ZIMG_SHA256=be89390f13a5c9b2388ce0f44a5e89364a20c1c57ce46d382b1fcc3967057577
ADD --checksum=sha256:$ZIMG_SHA256 $ZIMG_URL /zimg.tar.gz
RUN \
  tar $TAR_OPTS zimg.tar.gz && cd zimg-* && \
  ./autogen.sh && \
  ./configure \
    --disable-shared \
    --enable-static && \
  make -j$(nproc) install

FROM dep-filter-core AS dep-jxl

# bump: libjxl /LIBJXL_VERSION=([\d.]+)/ https://github.com/libjxl/libjxl.git|^0
# bump: libjxl after ./hashupdate Dockerfile LIBJXL $LATEST
# bump: libjxl link "Changelog" https://github.com/libjxl/libjxl/blob/main/CHANGELOG.md
# use bundled highway library as its static build is not available in alpine
ARG LIBJXL_VERSION=0.11.2
ARG LIBJXL_URL="https://github.com/libjxl/libjxl/archive/refs/tags/v$LIBJXL_VERSION.tar.gz"
ARG LIBJXL_SHA256=ab38928f7f6248e2a98cc184956021acb927b16a0dee71b4d260dc040a4320ea
ADD --checksum=sha256:$LIBJXL_SHA256 $LIBJXL_URL /libjxl.tar.gz
RUN \
  tar $TAR_OPTS libjxl.tar.gz && cd libjxl-* && \
  ./deps.sh && \
  cmake -B build \
    -G"Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TESTING=OFF \
    -DJPEGXL_ENABLE_PLUGINS=OFF \
    -DJPEGXL_ENABLE_BENCHMARK=OFF \
    -DJPEGXL_ENABLE_COVERAGE=OFF \
    -DJPEGXL_ENABLE_EXAMPLES=OFF \
    -DJPEGXL_ENABLE_FUZZERS=OFF \
    -DJPEGXL_ENABLE_SJPEG=OFF \
    -DJPEGXL_ENABLE_SKCMS=OFF \
    -DJPEGXL_ENABLE_VIEWERS=OFF \
    -DJPEGXL_FORCE_SYSTEM_GTEST=ON \
    -DJPEGXL_FORCE_SYSTEM_BROTLI=ON \
    -DJPEGXL_FORCE_SYSTEM_HWY=OFF && \
  cmake --build build -j$(nproc) && \
  cmake --install build
# workaround for ffmpeg configure script
RUN \
  sed -i 's/-ljxl/-ljxl -lstdc++ /' /usr/local/lib/pkgconfig/libjxl.pc && \
  sed -i 's/-ljxl_cms/-ljxl_cms -lstdc++ /' /usr/local/lib/pkgconfig/libjxl_cms.pc && \
  sed -i 's/-ljxl_threads/-ljxl_threads -lstdc++ /' /usr/local/lib/pkgconfig/libjxl_threads.pc

FROM base AS dep-zmq

# bump: libzmq /LIBZMQ_VERSION=([\d.]+)/ https://github.com/zeromq/libzmq.git|*
# bump: libzmq after ./hashupdate Dockerfile LIBZMQ $LATEST
# bump: libzmq link "NEWS" https://github.com/zeromq/libzmq/blob/master/NEWS
ARG LIBZMQ_VERSION=4.3.5
ARG LIBZMQ_URL="https://github.com/zeromq/libzmq/releases/download/v$LIBZMQ_VERSION/zeromq-$LIBZMQ_VERSION.tar.gz"
ARG LIBZMQ_SHA256=6653ef5910f17954861fe72332e68b03ca6e4d9c7160eb3a8de5a5a913bfab43
ADD --checksum=sha256:$LIBZMQ_SHA256 $LIBZMQ_URL /zmq.tar.gz
RUN \
  tar $TAR_OPTS zmq.tar.gz && cd zeromq-* && \
  # fix sha1_init symbol collision with libssh
  grep -r -l sha1_init external/sha1* | xargs sed -i 's/sha1_init/zeromq_sha1_init/g' && \
  ./configure \
    --disable-shared \
    --enable-static && \
  make -j$(nproc) install

FROM base AS dep-hw

# requires libdrm
# bump: libva /LIBVA_VERSION=([\d.]+)/ https://github.com/intel/libva.git|^2
# bump: libva after ./hashupdate Dockerfile LIBVA $LATEST
# bump: libva link "Changelog" https://github.com/intel/libva/blob/master/NEWS
ARG LIBVA_VERSION=2.23.0
ARG LIBVA_URL="https://github.com/intel/libva/archive/refs/tags/$LIBVA_VERSION.tar.gz"
ARG LIBVA_SHA256=b10aceb30e93ddf13b2030eb70079574ba437be9b3b76065caf28a72c07e23e7
ADD --checksum=sha256:$LIBVA_SHA256 $LIBVA_URL /libva.tar.gz
RUN \
  tar $TAR_OPTS libva.tar.gz && cd libva-* && \
  meson setup build \
    -Dbuildtype=release \
    -Ddefault_library=static \
    -Ddisable_drm=false \
    -Dwith_x11=no \
    -Dwith_glx=no \
    -Dwith_wayland=no \
    -Dwith_win32=no \
    -Dwith_legacy=[] \
    -Denable_docs=false && \
  ninja -j$(nproc) -vC build install

# bump: libvpl /LIBVPL_VERSION=([\d.]+)/ https://github.com/intel/libvpl.git|^2
# bump: libvpl after ./hashupdate Dockerfile LIBVPL $LATEST
# bump: libvpl link "Changelog" https://github.com/intel/libvpl/blob/main/CHANGELOG.md
ARG LIBVPL_VERSION=2.16.0
ARG LIBVPL_URL="https://github.com/intel/libvpl/archive/refs/tags/v$LIBVPL_VERSION.tar.gz"
ARG LIBVPL_SHA256=d60931937426130ddad9f1975c010543f0da99e67edb1c6070656b7947f633b6
ADD --checksum=sha256:$LIBVPL_SHA256 $LIBVPL_URL /libvpl.tar.gz
RUN \
  tar $TAR_OPTS libvpl.tar.gz && cd libvpl-* && \
  cmake -B build \
    -G"Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TESTS=OFF \
    -DENABLE_WARNING_AS_ERROR=ON && \
  cmake --build build -j$(nproc) && \
  cmake --install build
# not sure why this is needed, used to work
RUN sed -i 's/-lvpl /-lvpl -lstdc++ /' /usr/local/lib/pkgconfig/vpl.pc

FROM base AS dep-vvenc

# bump: vvenc /VVENC_VERSION=([\d.]+)/ https://github.com/fraunhoferhhi/vvenc.git|*
# bump: vvenc after ./hashupdate Dockerfile VVENC $LATEST
# bump: vvenc link "CHANGELOG" https://github.com/fraunhoferhhi/vvenc/releases/tag/v$LATEST
ARG VVENC_VERSION=1.14.0
ARG VVENC_URL="https://github.com/fraunhoferhhi/vvenc/archive/refs/tags/v$VVENC_VERSION.tar.gz"
ARG VVENC_SHA256=dd43d061d59dbc0d9b9ae5b99cb40672877dd811646228938f065798939ee174
ADD --checksum=sha256:$VVENC_SHA256 $VVENC_URL /vvenc.tar.gz
RUN \
  tar $TAR_OPTS vvenc.tar.gz && cd vvenc-* && \
  sed -i 's/-Werror;//' source/Lib/vvenc/CMakeLists.txt && \
  cmake \
    -S . \
    -B build/release-static \
    -DVVENC_ENABLE_WERROR=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr/local && \
  cmake --build build/release-static -j && \
  cmake --build build/release-static --target install

FROM base AS ffmpeg-build-base
COPY --from=dep-aom /usr/local/ /usr/local/
COPY --from=dep-subtitle /usr/local/ /usr/local/
COPY --from=dep-bluray /usr/local/ /usr/local/
COPY --from=dep-dav1d /usr/local/ /usr/local/
COPY --from=dep-fdkaac /usr/local/ /usr/local/
COPY --from=dep-audio-mp3 /usr/local/ /usr/local/
COPY --from=dep-filter-core /usr/local/ /usr/local/
COPY --from=dep-image /usr/local/ /usr/local/
COPY --from=dep-audio-opus /usr/local/ /usr/local/
COPY --from=dep-rabbitmq /usr/local/ /usr/local/
COPY --from=dep-rav1e /usr/local/ /usr/local/
COPY --from=dep-network-core /usr/local/ /usr/local/
COPY --from=dep-filter-extra /usr/local/ /usr/local/
COPY --from=dep-network-secure /usr/local/ /usr/local/
COPY --from=dep-svtav1 /usr/local/ /usr/local/
COPY --from=dep-audio-vorbis /usr/local/ /usr/local/
COPY --from=dep-vidstab /usr/local/ /usr/local/
COPY --from=dep-video-modern /usr/local/ /usr/local/
COPY --from=dep-zimg /usr/local/ /usr/local/
COPY --from=dep-jxl /usr/local/ /usr/local/
COPY --from=dep-zmq /usr/local/ /usr/local/
COPY --from=dep-hw /usr/local/ /usr/local/
COPY --from=dep-vvenc /usr/local/ /usr/local/

# bump: ffmpeg /FFMPEG_VERSION=([\d.]+)/ https://github.com/FFmpeg/FFmpeg.git|*
# bump: ffmpeg after ./hashupdate Dockerfile FFMPEG $LATEST
# bump: ffmpeg link "Changelog" https://github.com/FFmpeg/FFmpeg/blob/n$LATEST/Changelog
# bump: ffmpeg link "Source diff $CURRENT..$LATEST" https://github.com/FFmpeg/FFmpeg/compare/n$CURRENT..n$LATEST
ARG FFMPEG_VERSION=9.0
ARG FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.bz2"
ARG FFMPEG_SHA256=ce84a9d01766eacd271bef8fa6447593ccc691801b48ac4e7b9dc90a9483a422
RUN \
  wget $WGET_OPTS -O /ffmpeg.tar.bz2 "$FFMPEG_URL" && \
  echo "$FFMPEG_SHA256  /ffmpeg.tar.bz2" | sha256sum -c -
# sed changes --toolchain=hardened -pie to -static-pie
#
# ldflags stack-size=2097152 is to increase default stack size from 128KB (musl default) to something
# more similar to glibc (2MB). This fixing segfault with libaom-av1 and libsvtav1 as they seems to pass
# large things on the stack.
#
# ldfalgs -Wl,--allow-multiple-definition is a workaround for linking with multiple rust staticlib to
# not cause collision in toolchain symbols, see comment in checkdupsym script for details.
# Version ARGs are repeated in this stage because Docker ARG scope is per-stage.
ARG VMAF_VERSION=3.2.0
ARG AOM_VERSION=3.14.1
ARG LIBHARFBUZZ_VERSION=14.3.0
ARG LIBRSVG_VERSION=2.60.0
ARG LIBARIBB24_VERSION=1.0.3
ARG LIBASS_VERSION=0.17.5
ARG LIBBLURAY_VERSION=1.5.0
ARG DAV1D_VERSION=1.5.4
ARG FDK_AAC_VERSION=2.0.3
ARG MP3LAME_VERSION=3.100
ARG LCMS2_VERSION=2.19.1
ARG LIBMYSOFA_VERSION=1.3.5
ARG OPENJPEG_VERSION=2.5.4
ARG OPUS_VERSION=1.6.1
ARG LIBRABBITMQ_VERSION=0.17.0
ARG RAV1E_VERSION=0.7.1
ARG LIBRTMP_COMMIT=138fdb258d9fc26f1843fd1b891180416c9dc575
ARG RUBBERBAND_VERSION=2.0.2
ARG SRT_VERSION=1.5.6
ARG LIBSSH_VERSION=0.12.1
ARG SVTAV1_VERSION=4.2.0
ARG OGG_VERSION=1.3.6
ARG VORBIS_VERSION=1.3.7
ARG VIDSTAB_VERSION=1.1.2
ARG VPX_VERSION=1.16.0
ARG LIBWEBP_VERSION=1.6.0
ARG X264_VERSION=b35605ace3ddf7c1a5d67a2eb553f034aef41d55
ARG X265_VERSION=4.2
ARG ZIMG_VERSION=3.0.6
ARG LIBJXL_VERSION=0.11.2
ARG LIBZMQ_VERSION=4.3.5
ARG LIBVA_VERSION=2.23.0
ARG LIBVPL_VERSION=2.16.0
ARG VVENC_VERSION=1.14.0
ARG MIMALLOC_VERSION=2.4.5
RUN \
  git clone -b v$MIMALLOC_VERSION --depth 1 https://github.com/microsoft/mimalloc.git mimalloc && \
  cd mimalloc && \
  mkdir build && \
  cd build && \
  cmake -D CMAKE_BUILD_TYPE=Release -DMI_OVERRIDE=OFF -DMI_INSTALL_TOPLEVEL=ON .. && \
  cmake --build . --config=Release && \
  make install

ADD patches/* ./patches/

FROM ffmpeg-build-base AS builder
ARG ENABLE_FDKAAC=
ARG BUILD_VARIANT=default

RUN \
  tar $TAR_OPTS ffmpeg.tar.bz2 && cd ffmpeg* && \
  patch -u <../patches/mimalloc.patch && \
  DEFAULT_VARIANT_FLAGS=" --disable-encoders --disable-decoders --enable-encoder=aac,ac3,ac3_fixed,apng,av1_qsv,flac,gif,h264_qsv,h264_v4l2m2m,hevc_qsv,hevc_v4l2m2m,jpeg2000,jpegls,libaom_av1,libjxl,libmp3lame,libopenjpeg,libopus,librav1e,libsvtav1,libvorbis,libvpx_vp8,libvpx_vp9,libvvenc,libwebp,libwebp_anim,libx264,libx264rgb,libx265,ljpeg,mjpeg,mjpeg_qsv,mpeg2_qsv,mpeg2video,opus,png,rawvideo,text,tiff,vp8_v4l2m2m,vp9_qsv,webvtt,yuv4,zlib --enable-decoder=aac,aac_fixed,aac_latm,ac3,ac3_fixed,apng,av1,av1_qsv,flac,flv,gif,h261,h263,h263_v4l2m2m,h263i,h263p,h264,h264_qsv,h264_v4l2m2m,hevc,hevc_qsv,hevc_v4l2m2m,jpeg2000,jpegls,libaom_av1,libaribb24,libdav1d,libjxl,libopus,librsvg,libvorbis,libvpx_vp8,libvpx_vp9,mjpeg,mjpeg_qsv,mjpegb,mp3,mp3adu,mp3adufloat,mp3float,mp3on4,mp3on4float,mpeg1video,mpeg2_qsv,mpeg2_v4l2m2m,mpeg2video,mpeg4,mpeg4_v4l2m2m,mpegvideo,msmpeg4v1,msmpeg4v2,msmpeg4v3,opus,pcm_s16le,png,rawvideo,srt,text,tiff,vc1,vorbis,vp7,vp8,vp8_qsv,vp8_v4l2m2m,vp9,vp9_qsv,vp9_v4l2m2m,vvc,vvc_qsv,wavpack,wbmp,webp,webvtt,wmv1,wmv2,wmv3,wmv3image,wrapped_avframe,yuv4,zlib" && \
  SLIM_VARIANT_FLAGS=" --disable-encoders --disable-decoders --disable-filters --enable-encoder=aac,ac3,ac3_fixed,apng,av1_qsv,flac,gif,h264_qsv,h264_v4l2m2m,hevc_qsv,hevc_v4l2m2m,jpeg2000,jpegls,libaom_av1,libjxl,libmp3lame,libopenjpeg,libopus,librav1e,libsvtav1,libvpx_vp8,libvpx_vp9,libvvenc,libwebp,libwebp_anim,libx264,libx264rgb,libx265,ljpeg,mjpeg,mjpeg_qsv,mpeg2_qsv,mpeg2video,opus,png,rawvideo,text,tiff,vp9_qsv,webvtt,yuv4,zlib --enable-decoder=aac,aac_fixed,aac_latm,ac3,ac3_fixed,alac,apng,av1,av1_qsv,flac,gif,h264,h264_qsv,h264_v4l2m2m,hevc,hevc_qsv,hevc_v4l2m2m,jpeg2000,jpegls,libaom_av1,libdav1d,libjxl,libopus,libvpx_vp8,libvpx_vp9,mjpeg,mjpeg_qsv,mjpegb,mp3,mp3float,mpeg2_qsv,mpeg2_v4l2m2m,mpeg2video,mpeg4,mpeg4_v4l2m2m,opus,pcm_s16le,png,rawvideo,srt,text,tiff,vorbis,vp8,vp8_qsv,vp8_v4l2m2m,vp9,vp9_qsv,vp9_v4l2m2m,vvc,vvc_qsv,webp,webvtt,wrapped_avframe,yuv4,zlib --enable-filter=acompressor,acontrast,acopy,acrossfade,adelay,aecho,afade,afftdn,afir,aformat,agate,alimiter,allpass,amerge,amix,amovie,anequalizer,anlmdn,anull,anullsink,anullsrc,apad,aphasemeter,aresample,areverse,aselect,asetnsamples,asetpts,asetrate,asettb,ashowinfo,asplit,astats,atempo,atrim,bandpass,bandreject,bass,biquad,channelmap,channelsplit,chorus,compand,concat,crossfeed,dcshift,deesser,dynaudnorm,earwax,ebur128,equalizer,firequalizer,flanger,haas,hdcd,highpass,loudnorm,lowpass,mcompand,pan,replaygain,rubberband,silencedetect,silenceremove,sine,sofalizer,stereotools,stereowiden,superequalizer,volume,volumedetect,addroi,alphaextract,alphamerge,ass,avgblur,azmq,bbox,blackdetect,blackframe,blend,blurdetect,bwdif,chromakey,chromanr,color,colorbalance,colorchannelmixer,colorlevels,colorkey,colormatrix,colorspace,convolution,crop,cropdetect,curves,decimate,dejudder,delogo,deshake,drawbox,drawgrid,drawtext,eq,fade,fieldmatch,fillborders,format,fps,framerate,freezedetect,gblur,gradfun,hflip,histeq,hqdn3d,hstack,hue,hwdownload,hwmap,hwupload,idet,interlace,lenscorrection,libvmaf,lut,lut1d,lut2,lut3d,lutrgb,lutyuv,mergeplanes,minterpolate,movie,mpdecimate,msad,negate,nlmeans,noformat,null,nullsink,nullsrc,overlay,pad,palettegen,paletteuse,perspective,premultiply,psnr,pullup,remap,rotate,scale,scale2ref,select,separatefields,setdar,setfield,setparams,setpts,setrange,setsar,settb,showinfo,showpalette,signature,signalstats,siti,smartblur,split,ssim,subtitles,testsrc,testsrc2,thumbnail,tile,tonemap,transpose,trim,unpremultiply,unsharp,vidstabdetect,vidstabtransform,vif,vmafmotion,w3fdif,xpsnr,xstack,yadif,yuvtestsrc,zmq,zscale,deinterlace_qsv,hstack_qsv,overlay_qsv,scale_qsv,vpp_qsv,vstack_qsv,xstack_qsv,smptebars,smptehdbars" && \
  case "$BUILD_VARIANT" in \
    full) VARIANT_FLAGS="" ;; \
    default) VARIANT_FLAGS="$DEFAULT_VARIANT_FLAGS" ;; \
    slim) VARIANT_FLAGS="$SLIM_VARIANT_FLAGS" ;; \
    *) echo "Unsupported BUILD_VARIANT=$BUILD_VARIANT" >&2; exit 1 ;; \
  esac && \
  FDKAAC_FLAGS=$(if [[ -n "$ENABLE_FDKAAC" ]] ;then echo " --enable-libfdk-aac --enable-nonfree --enable-encoder=libfdk_aac --enable-decoder=libfdk_aac " ;else echo ""; fi) && \
  sed -i 's/add_ldexeflags -fPIE -pie/add_ldexeflags -fPIE -static-pie/' configure && \
  ./configure \
  --custom_allocator=mimalloc \
  --pkg-config-flags="--static" \
  --extra-cflags="-fopenmp -O3" \
  --extra-ldflags="-fopenmp -Wl,--allow-multiple-definition -Wl,-z,stack-size=2097152" \
  --toolchain=hardened \
  --disable-debug \
  --disable-shared \
  --disable-ffplay \
  --enable-static \
  --enable-gpl \
  --enable-version3 \
  $VARIANT_FLAGS \
  $FDKAAC_FLAGS \
  --enable-fontconfig \
  --enable-gray \
  --enable-iconv \
  --enable-lcms2 \
  --enable-libaom \
  --enable-libaribb24 \
  --enable-libass \
  --enable-libbluray \
  --enable-libdav1d \
  --enable-libfreetype \
  --enable-libfribidi \
  --enable-libharfbuzz \
  --enable-libjxl \
  --enable-libmp3lame \
  --enable-libmysofa \
  --enable-libopenjpeg \
  --enable-libopus \
  --enable-librabbitmq \
  --enable-librav1e \
  --enable-librsvg \
  --enable-librtmp \
  --enable-librubberband \
  --enable-libsnappy \
  --enable-libsoxr \
  --enable-libsrt \
  --enable-libssh \
  --enable-libsvtav1 \
  --enable-libvidstab \
  --enable-libvmaf \
  --enable-libvorbis \
  --enable-libvpl \
  --enable-libvpx \
  --enable-libvvenc \
  --enable-libwebp \
  --enable-libx264 \
  --enable-libx265 \
  --enable-libxml2 \
  --enable-libzimg \
  --enable-libzmq \
  --enable-openssl \
  --disable-network \
  || (cat ffbuild/config.log ; false) \
  && make -j$(nproc) install

RUN \
  EXPAT_VERSION=$(pkg-config --modversion expat) \
  FFTW_VERSION=$(pkg-config --modversion fftw3) \
  FONTCONFIG_VERSION=$(pkg-config --modversion fontconfig) \
  FREETYPE_VERSION=$(pkg-config --modversion freetype2) \
  FRIBIDI_VERSION=$(pkg-config --modversion fribidi) \
  LIBSAMPLERATE_VERSION=$(pkg-config --modversion samplerate) \
  LIBXML2_VERSION=$(pkg-config --modversion libxml-2.0) \
  OPENSSL_VERSION=$(pkg-config --modversion openssl) \
  SNAPPY_VERSION=$(apk info -a snappy $APK_OPTS | head -n1 | awk '{print $1}' | sed -e 's/snappy-//') \
  SOXR_VERSION=$(pkg-config --modversion soxr) \
  jq -n \
  '{ \
  variant: env.BUILD_VARIANT, \
  expat: env.EXPAT_VERSION, \
  "libfdk-aac": env.FDK_AAC_VERSION, \
  ffmpeg: env.FFMPEG_VERSION, \
  fftw: env.FFTW_VERSION, \
  fontconfig: env.FONTCONFIG_VERSION, \
  lcms2: env.LCMS2_VERSION, \
  libaom: env.AOM_VERSION, \
  libaribb24: env.LIBARIBB24_VERSION, \
  libass: env.LIBASS_VERSION, \
  libbluray: env.LIBBLURAY_VERSION, \
  libdav1d: env.DAV1D_VERSION, \
  libfreetype: env.FREETYPE_VERSION, \
  libfribidi: env.FRIBIDI_VERSION, \
  libharfbuzz: env.LIBHARFBUZZ_VERSION, \
  libjxl: env.LIBJXL_VERSION, \
  libmp3lame: env.MP3LAME_VERSION, \
  libmysofa: env.LIBMYSOFA_VERSION, \
  mimalloc: env.MIMALLOC_VERSION, \
  libogg: env.OGG_VERSION, \
  libopenjpeg: env.OPENJPEG_VERSION, \
  libopus: env.OPUS_VERSION, \
  librabbitmq: env.LIBRABBITMQ_VERSION, \
  librav1e: env.RAV1E_VERSION, \
  librsvg: env.LIBRSVG_VERSION, \
  librtmp: env.LIBRTMP_COMMIT, \
  librubberband: env.RUBBERBAND_VERSION, \
  libsamplerate: env.LIBSAMPLERATE_VERSION, \
  libsnappy: env.SNAPPY_VERSION, \
  libsoxr: env.SOXR_VERSION, \
  libsrt: env.SRT_VERSION, \
  libssh: env.LIBSSH_VERSION, \
  libsvtav1: env.SVTAV1_VERSION, \
  libva: env.LIBVA_VERSION, \
  libvidstab: env.VIDSTAB_VERSION, \
  libvmaf: env.VMAF_VERSION, \
  libvorbis: env.VORBIS_VERSION, \
  libvpl: env.LIBVPL_VERSION, \
  libvpx: env.VPX_VERSION, \
  libvvenc: env.VVENC_VERSION, \
  libwebp: env.LIBWEBP_VERSION, \
  libx264: env.X264_VERSION, \
  libx265: env.X265_VERSION, \
  libxml2: env.LIBXML2_VERSION, \
  libzimg: env.ZIMG_VERSION, \
  libzmq: env.LIBZMQ_VERSION, \
  openssl: env.OPENSSL_VERSION, \
  }' > /versions.json

# make sure binaries has no dependencies, is relro, pie and stack nx
COPY checkelf /
RUN \
  /checkelf /usr/local/bin/ffmpeg && \
  /checkelf /usr/local/bin/ffprobe
# workaround for using -Wl,--allow-multiple-definition
# see comment in checkdupsym for details
COPY checkdupsym /
RUN /checkdupsym /ffmpeg-*

# some basic fonts that don't take up much space
RUN apk add $APK_OPTS font-terminus font-inconsolata font-dejavu font-awesome

FROM scratch AS final1
COPY --from=builder /usr/local/bin/ffmpeg /
COPY --from=builder /usr/local/bin/ffprobe /
COPY --from=builder /versions.json /
COPY --from=builder /usr/local/share/doc/ffmpeg/* /doc/
COPY --from=builder /etc/ssl/cert.pem /etc/ssl/cert.pem
COPY --from=builder /etc/fonts/ /etc/fonts/
COPY --from=builder /usr/share/fonts/ /usr/share/fonts/
COPY --from=builder /usr/share/consolefonts/ /usr/share/consolefonts/
COPY --from=builder /var/cache/fontconfig/ /var/cache/fontconfig/

# sanity tests
RUN ["/ffmpeg", "-version"]
RUN ["/ffprobe", "-version"]
RUN ["/ffmpeg", "-hide_banner", "-buildconf"]
# stack size
RUN ["/ffmpeg", "-f", "lavfi", "-i", "testsrc", "-c:v", "libsvtav1", "-t", "100ms", "-f", "null", "-"]
# vvenc
RUN ["/ffmpeg", "-f", "lavfi", "-i", "testsrc", "-c:v", "libvvenc", "-t", "100ms", "-f", "null", "-"]
# x265 regression
RUN ["/ffmpeg", "-f", "lavfi", "-i", "testsrc", "-c:v", "libx265", "-t", "100ms", "-f", "null", "-"]

# clamp all files into one layer
FROM scratch AS final2
COPY --from=final1 / /

FROM final2
LABEL maintainer="Hugefiver <i@iruri.moe>"
ENTRYPOINT ["/ffmpeg"]
