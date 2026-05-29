FROM ubuntu:20.04 AS build
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    build-essential \
    cmake \
    pkg-config \
    qt5-default \
    libqt5opengl5-dev \
    libgl1-mesa-dev \
    libglu1-mesa-dev \
    libprotobuf-dev \
    protobuf-compiler \
    libode-dev \
    libboost-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /vartypes
RUN git clone https://github.com/jpfeltracco/vartypes.git . && \
    git checkout 2d16e81b7995f25c5ba5e4bc31bf9a514ee4bc42 && \
    mkdir -p build && \
    cd build && \
    cmake .. && \
    make && \
    make install && \
    ldconfig

WORKDIR /firasim
COPY cmake /firasim/cmake
COPY config /firasim/config
COPY include /firasim/include
COPY resources /firasim/resources
COPY formation /firasim/formation
COPY msg /firasim/msg
COPY src /firasim/src
COPY CMakeLists.txt README.md LICENSE.md INSTALL.md AUTHORS.md CHANGELOG.md /firasim/

RUN mkdir -p /usr/local/share/firasim
COPY firasim.xml /usr/local/share/firasim/grsim.xml

RUN mkdir -p /usr/local/share/grsim/config
COPY config/*.ini /usr/local/share/grsim/config/

RUN mkdir -p build && \
    cd build && \
    cmake -DCMAKE_INSTALL_PREFIX=/usr/local .. && \
    make && \
    make install && \
    ldconfig


FROM ubuntu:20.04
ENV DEBIAN_FRONTEND=noninteractive \
    LD_LIBRARY_PATH=/lib:/usr/lib:/usr/local/lib

RUN apt-get update && apt-get install -y --no-install-recommends \
        tini \
        qt5-default \
        libqt5opengl5 \
        libode8 \
        libprotobuf17 \
        xvfb \
        x11vnc \
        x11-utils \
        libgl1-mesa-dri \
        libgl1-mesa-glx \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /usr/local /usr/local

RUN useradd -ms /bin/bash default
COPY docker-entry.sh /docker-entry.sh
RUN chmod 775 /docker-entry.sh

EXPOSE 20011 30011 30012 10300 10301 10302 5900
USER default
WORKDIR /home/default
ENTRYPOINT ["tini", "--", "/docker-entry.sh"]
