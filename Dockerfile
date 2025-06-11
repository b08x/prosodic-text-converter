# Multi-stage Dockerfile for Prosodic Text Converter
# Based on Ubuntu 22.04 for better Qt library compatibility
# Addresses DEVOPS-001 task requirements

# ================================
# Builder Stage
# ================================
FROM rubylang/ruby:3.4.3-jammy AS builder

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Update package lists and install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    # System essentials
    ca-certificates \
    curl \
    wget \
    git \
    mercurial \
    unzip \
    # Build tools
    build-essential \
    cmake \
    ninja-build \
    pkg-config \
    autoconf \
    automake \
    libtool \
    # Ruby and development headers
    ruby \
    ruby-dev \
    # Audio processing tools
    sox \
    imagemagick \
    aubio-tools \
    # Qt6 development libraries (Ubuntu 22.04 has good Qt6 support)
    qt6-base-dev \
    qt6-base-dev-tools \
    qt6-tools-dev \
    qt6-tools-dev-tools \
    qtchooser \
    # Sonic-annotator build dependencies
    libbz2-dev \
    libfftw3-dev \
    libfishsound1-dev \
    libid3tag0-dev \
    libmad0-dev \
    liboggz2-dev \
    libopus-dev \
    libopusfile-dev \
    libsamplerate0-dev \
    libsndfile1-dev \
    libsord-dev \
    libxml2-utils \
    yajl-tools \
    raptor2-utils \
    libglib2.0-dev \
    # Additional Qt6 multimedia and network components
    qt6-multimedia-dev \
    libqt6network6 \
    libqt6xml6 \
    # Python for some build scripts
    python3 \
    python3-pip \
    # Cleanup in same layer
    && rm -rf /var/lib/apt/lists/*

# Install Ruby Bundler
RUN gem install bundler

# Install Meson build system (required for some dependencies)
RUN pip3 install meson

# Set Qt6 as default
RUN qtchooser -install qt6 $(which qmake6) || echo "Qt6 qmake setup complete"
ENV QT_SELECT=qt6


# Install Vamp SDK (tarball uses autotools, not CMake)
RUN cd /tmp && \
    wget https://code.soundsoftware.ac.uk/attachments/download/2691/vamp-plugin-sdk-2.10.0.tar.gz && \
    tar xf vamp-plugin-sdk-2.10.0.tar.gz && \
    cd vamp-plugin-sdk-2.10.0 && \
    ./configure --prefix=/usr/local && \
    make && make install && \
    ldconfig && \
    cd / && rm -rf /tmp/vamp-plugin-sdk-2.10.0*

# Create Vamp plugin directory
RUN mkdir -p /usr/local/lib/vamp

# Build essential Vamp plugins
RUN cd /tmp && \
    # pYIN plugin for pitch tracking (pre-compiled binary)
    wget https://code.soundsoftware.ac.uk/attachments/download/2631/pyin-v1.2-linux64.tar.gz && \
    tar xf pyin-v1.2-linux64.tar.gz && \
    cp pyin-v1.2-linux64/pyin.so /usr/local/lib/vamp/ && \
    cd /tmp && \
    \
    # Vamp example plugins (includes fixedtempo) - pre-compiled binaries
    wget https://code.soundsoftware.ac.uk/attachments/download/2693/vamp-plugin-sdk-2.10.0-binaries-amd64-linux.tar.gz && \
    tar xf vamp-plugin-sdk-2.10.0-binaries-amd64-linux.tar.gz && \
    find vamp-plugin-sdk-2.10.0-binaries-amd64-linux -name "*.so" -exec cp {} /usr/local/lib/vamp/ \; && \
    cd /tmp && \
    \
    # Aubio Vamp plugins (pre-compiled binary)
    wget https://aubio.org/bin/vamp-aubio-plugins/0.5.1/vamp-aubio-plugins-0.5.1-x86_64.tar.bz2 && \
    tar xf vamp-aubio-plugins-0.5.1-x86_64.tar.bz2 && \
    cp vamp-aubio-plugins-0.5.1-x86_64/*.so /usr/local/lib/vamp/ && \
    cd /tmp && \
    \
    # Clean up
    rm -rf /tmp/pyin-v1.2-linux64* /tmp/vamp-plugin-sdk-2.10.0-binaries-amd64-linux* /tmp/vamp-aubio-plugins-*

# Build sonic-annotator from source with proper Qt6 support
RUN cd /tmp && \
    wget https://github.com/sonic-visualiser/sonic-annotator/releases/download/sonic-annotator-1.7/sonic-annotator-1.7.tar.gz && \
    tar xf sonic-annotator-1.7.tar.gz && \
    cd sonic-annotator-1.7 && \
    # Configure Qt6 environment and build
    QT_SELECT=qt6 meson setup build --buildtype release && \
    # Build with ninja
    ninja -C build && \
    # Install binary
    cp build/sonic-annotator /usr/local/bin/ && \
    chmod +x /usr/local/bin/sonic-annotator && \
    # Verify the build
    /usr/local/bin/sonic-annotator --version && \
    cd / && rm -rf /tmp/sonic-annotator-1.7*

# Set working directory for Ruby application
WORKDIR /app

# Copy dependency files first for better Docker layer caching
COPY Gemfile Gemfile.lock ./

# # Install Ruby gems
# RUN bundle config set --local deployment 'true' \
#     && bundle config set --local without 'development test' \
#     && bundle install

RUN export GEM_HOME="${HOME}/.local/share/gem/ruby/3.4.0" && \
    export PATH="${HOME}/.local/share/gem/ruby/3.4.0/bin:${PATH}" && \
    bundle lock --add-platform x86_64-linux && \
    bundle config build.redic --with-cxx="clang++" --with-cflags="-std=c++0x" && \
    bundle install

# Copy application files
COPY . .

# Make scripts executable
RUN chmod +x bin/prosodic-text-converter

# Create necessary directories
RUN mkdir -p spectrograms output transforms

# Update library cache for Vamp plugins
RUN ldconfig

# ================================
# Final Production Stage
# ================================
FROM rubylang/ruby:3.4.3-jammy AS production

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install only runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    # System essentials
    ca-certificates \
    # Ruby runtime
    ruby \
    # Audio processing runtime
    sox \
    imagemagick \
    aubio-tools \
    libqt6core6 \
    libqt6gui6 \
    libqt6widgets6 \
    libqt6network6 \
    libqt6xml6 \
    # Sonic-annotator runtime dependencies
    libbz2-1.0 \
    libfftw3-3 \
    libfishsound1 \
    libid3tag0 \
    libmad0 \
    liboggz2 \
    libopus0 \
    libopusfile0 \
    libsamplerate0 \
    libsndfile1 \
    libsord-0-0 \
    libglib2.0-0 \
    # Cleanup
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN groupadd -r prosodic && useradd -r -g prosodic prosodic

# Set working directory
WORKDIR /app

# Copy Ruby from builder
COPY --from=builder \
  /usr/local/bin/bundle \
  /usr/local/bin/bundler \
  /usr/local/bin/erb \
  /usr/local/bin/gem \
  /usr/local/bin/irb \
  /usr/local/bin/racc \
  /usr/local/bin/rake \
  /usr/local/bin/rdoc \
  /usr/local/bin/ri \
  /usr/local/bin/ruby \
  /usr/local/bin/

COPY --from=builder \
  /usr/local/include/ruby-3.4.0/ \
  /usr/local/include/ruby-3.4.0/

COPY --from=builder \
  /usr/local/lib/libruby.so* \
  /usr/local/lib/

COPY --from=builder \
  /usr/local/lib/pkgconfig/ \
  /usr/local/lib/pkgconfig/

COPY --from=builder \
  /usr/local/lib/ruby/ \
  /usr/local/lib/ruby/

COPY --from=builder \
  /usr/local/share/man/man1/erb.1 \
  /usr/local/share/man/man1/irb.1 \
  /usr/local/share/man/man1/ri.1 \
  /usr/local/share/man/man1/ruby.1 \
  /usr/local/share/man/man1/

# Copy installed gems from builder
COPY --from=builder --chown=prosodic:prosodic \
  /root/.local/share/gem/ \
  /home/prosodic/.local/share/gem/

COPY --from=builder --chown=prosodic:prosodic \
  /app/Gemfile \
  /app/Gemfile.lock \
  /home/prosodic/

# Copy sonic-annotator binary from builder stage
COPY --from=builder /usr/local/bin/sonic-annotator /usr/local/bin/sonic-annotator

# Copy Vamp SDK and plugins from builder stage
COPY --from=builder /usr/local/lib/vamp/ /usr/local/lib/vamp/
COPY --from=builder /usr/local/lib/libvamp* /usr/local/lib/
COPY --from=builder /usr/local/include/vamp-sdk/ /usr/local/include/vamp-sdk/

# Copy application files from builder stage
COPY --from=builder --chown=prosodic:prosodic /app /app

# Update library cache for Vamp plugins
RUN ldconfig

# Create volume mounts for input/output
RUN mkdir -p /app/input /app/output /app/spectrograms \
    && chown -R prosodic:prosodic /app

# Switch to non-root user
USER prosodic

ENV PATH="/home/prosodic/.local/share/gem/ruby/3.4.0/bin:${HOME}/.local/bin:${PATH}"
ENV GEM_HOME="/home/prosodic/.local/share/gem/ruby/3.4.0"

# Expose volume for input files, output files, and spectrograms
VOLUME ["/app/input", "/app/output", "/app/spectrograms"]

# Set environment variables
ENV PROSODIC_PITCH_BACKEND=aubio
ENV BUNDLE_DEPLOYMENT=true
ENV BUNDLE_WITHOUT=development:test
ENV QT_SELECT=qt6

# Health check to verify dependencies
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD ruby bin/prosodic-text-converter --health-check || exit 1

# Set entrypoint to the main application script
ENTRYPOINT ["ruby", "bin/prosodic-text-converter"]

# Default command shows help
CMD ["--help"]