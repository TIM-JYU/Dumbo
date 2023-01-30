ARG TIM_IMAGE_TAG

FROM fpco/stack-build:lts-18.13 AS build
LABEL author="Ville Tirronen"
LABEL maintainer="help@tim.education"

ENV APT_INSTALL="DEBIAN_FRONTEND=noninteractive apt-get -qq update && DEBIAN_FRONTEND=noninteractive apt-get -q install --no-install-recommends -y" \
    APT_CLEANUP="rm -r /var/lib/apt/lists/*"

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN stack update

WORKDIR /build
COPY LICENSE ./
COPY stack.yaml ./
COPY Dumbo.cabal ./
COPY AsciiMath ./AsciiMath

# RUN stack solver --system-ghc --update-config
RUN stack build --only-dependencies

COPY *.hs ./

RUN stack build --copy-bins

FROM ubuntu:22.04 as runtime
# Copied from timimages/tim for caching
ENV APT_INSTALL="DEBIAN_FRONTEND=noninteractive apt-get -qq update && DEBIAN_FRONTEND=noninteractive apt-get -q install --no-install-recommends -y" \
    APT_CLEANUP="rm -rf /var/lib/apt/lists /dvisvgm-2.4 /usr/share/doc ~/.cache"

# Configure timezone and locale
RUN bash -c "${APT_INSTALL} locales tzdata && ${APT_CLEANUP}"
RUN locale-gen en_US.UTF-8 && bash -c "${APT_CLEANUP}"
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8
RUN echo "Europe/Helsinki" > /etc/timezone; dpkg-reconfigure -f noninteractive tzdata && bash -c "${APT_CLEANUP}"

# Install dependencies of texlive-full excluding packages that are not needed (such as documentation files).
# This almost-full installation of TeX Live is needed for the latex-pdf printing functionality, as
# TeX Live doesn't have an (MiKTeX/MacTeX-esque) auto-install functionality for missing LaTeX packages,
# i.e. the whole package archive needs to be pre-installed or the set of usable packages needs to be
# severely limited.
RUN bash -c "${APT_INSTALL} \
    biber \
    ca-certificates \
    cm-super \
    dvidvi \
    dvipng \
    feynmf \
    fonts-texgyre \
    fragmaster \
    latex-cjk-all \
    latexmk \
    lcdf-typetools \
    lmodern \
    psutils \
    purifyeps \
    software-properties-common \
    t1utils \
    tex-gyre \
    texlive-base \
    texlive-bibtex-extra \
    texlive-binaries \
    texlive-extra-utils \
    texlive-font-utils \
    texlive-fonts-extra \
    texlive-fonts-recommended \
    texlive-formats-extra \
    texlive-games \
    texlive-humanities \
    texlive-lang-arabic \
    texlive-lang-chinese \
    texlive-lang-cjk \
    texlive-lang-cyrillic \
    texlive-lang-czechslovak \
    texlive-lang-english \
    texlive-lang-european \
    texlive-lang-french \
    texlive-lang-german \
    texlive-lang-greek \
    texlive-lang-italian \
    texlive-lang-japanese \
    texlive-lang-korean \
    texlive-lang-other \
    texlive-lang-polish \
    texlive-lang-portuguese \
    texlive-lang-spanish \
    texlive-latex-base \
    texlive-latex-extra \
    texlive-latex-recommended \
    texlive-luatex \
    texlive-metapost \
    texlive-music \
    texlive-pictures \
    texlive-pstricks \
    texlive-publishers \
    texlive-science \
    texlive-xetex \
    wget \
    && ${APT_CLEANUP}"

# Install gpg and gpg-agent for verifying signatures
RUN bash -c "${APT_INSTALL} gpg-agent && ${APT_CLEANUP}"

# Update dvisvgm so that it supports converting PDFs to SVGs
ENV DVISVGM_VERSION="2.14"
RUN bash -c "${APT_INSTALL} gcc g++ libgs-dev libkpathsea-dev pkg-config libfreetype6-dev make && ${APT_CLEANUP}"
RUN FILE=`mktemp`; wget "https://github.com/mgieseki/dvisvgm/releases/download/${DVISVGM_VERSION}/dvisvgm-${DVISVGM_VERSION}.tar.gz" -qO $FILE && \
    tar -xf $FILE && \
    cd dvisvgm-$DVISVGM_VERSION && \
    ./configure --enable-bundled-libs && \
    make -j4 && \
    make install && \
    cd / && \
    ${APT_CLEANUP} && \
    rm -rf /dvisvgm-$DVISVGM_VERSION

COPY --from=build /root/.local/bin/Dumbo /Dumbo/
WORKDIR /Dumbo
VOLUME [ "/dumbo_cache", "/dumbo_tmp" ]
CMD [ "./Dumbo", "--port", "5000", "--cacheDir", "/dumbo_cache", "--tmpDir", "/dumbo_tmp" ]
