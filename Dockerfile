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

# Use base TIM image which includes TeX and DVISVG
FROM ghcr.io/tim-jyu/tim-base:latest as runtime

COPY --from=build /root/.local/bin/Dumbo /Dumbo/
WORKDIR /Dumbo
VOLUME [ "/dumbo_cache", "/dumbo_tmp" ]
CMD [ "./Dumbo", "--port", "5000", "--cacheDir", "/dumbo_cache", "--tmpDir", "/dumbo_tmp" ]
