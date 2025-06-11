# Multi-stage Dockerfile for Prosodic Text Converter
# Based on the DEVOPS-001 task requirements

# ================================
# Builder Stage
# ================================
FROM ruby:3.4.3 AS builder

# Install build dependencies and runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build tools
    build-essential \
    ruby-dev \
    pkg-config \
    autoconf \
    automake \
    libtool \
    ninja-build \
    # Audio processing tools
    sox \
    imagemagick \
    aubio-tools \
    # Sonic-annotator build dependencies
    libbz2-dev \
    libfftw3-dev \
    libfishsound1-dev \
    libid3tag0-dev \
    libmad0-dev \
    liboggz2-dev \
    libopus-dev \
    libopusfile-dev \
    libsamplerate-dev \
    libsndfile-dev \
    libsord-dev \
    libxml2-utils \
    qt6-base-dev \
    qt6-base-dev-tools \
    yajl-tools \
    raptor2-utils \
    libglib2.0-dev \
    # Version control and network tools
    git \
    mercurial \
    wget \
    curl \
    ca-certificates \
    # Cleanup
    && rm -rf /var/lib/apt/lists/*

# Install Meson build system
RUN mkdir -p /tmp/meson && \
    cd /tmp/meson && \
    wget https://github.com/mesonbuild/meson/releases/download/1.3.1/meson-1.3.1.tar.gz && \
    tar xf meson-1.3.1.tar.gz && \
    ln -s /tmp/meson/meson-1.3.1/meson.py /usr/bin/meson

# Install Vamp SDK first
RUN cd /tmp && \
    wget https://code.soundsoftware.ac.uk/attachments/download/2691/vamp-plugin-sdk-2.10.0.tar.gz && \
    tar xf vamp-plugin-sdk-2.10.0.tar.gz && \
    cd vamp-plugin-sdk-2.10.0 && \
    ./configure --prefix=/usr/local && \
    make && make install && \
    ldconfig && \
    cd / && rm -rf /tmp/vamp-plugin-sdk-2.10.0*

# Build essential Vamp plugins
RUN cd /tmp && \
    # pYIN plugin for pitch tracking
    git clone https://github.com/matthiasmayr/pyin.git && \
    cd pyin && \
    make -f Makefile.linux && \
    cp pyin.so /usr/local/lib/vamp/ && \
    cd /tmp && \
    \
    # Vamp example plugins (includes fixedtempo)
    wget https://code.soundsoftware.ac.uk/attachments/download/2692/vamp-example-plugins-2.10.0.tar.gz && \
    tar xf vamp-example-plugins-2.10.0.tar.gz && \
    cd vamp-example-plugins-2.10.0 && \
    make -f Makefile.linux && \
    cp *.so /usr/local/lib/vamp/ && \
    cd /tmp && \
    \
    # Aubio Vamp plugins
    wget https://aubio.org/pub/vamp-aubio-plugins-0.5.1.tar.bz2 && \
    tar xf vamp-aubio-plugins-0.5.1.tar.bz2 && \
    cd vamp-aubio-plugins-0.5.1 && \
    make -f Makefile.linux && \
    cp *.so /usr/local/lib/vamp/ && \
    cd /tmp && \
    \
    # Clean up
    rm -rf /tmp/pyin /tmp/vamp-example-plugins-* /tmp/vamp-aubio-plugins-*

# Build sonic-annotator from source
RUN cd /tmp && \
    wget https://github.com/sonic-visualiser/sonic-annotator/releases/download/sonic-annotator-1.7/sonic-annotator-1.7.tar.gz && \
    tar xf sonic-annotator-1.7.tar.gz && \
    cd sonic-annotator-1.7 && \
    ./repoint install && \
    qtchooser -install qt6 $(which qmake6) && \
    QT_SELECT=qt6 meson setup build --buildtype release && \
    ninja -C build && \
    cp build/sonic-annotator /usr/local/bin/ && \
    chmod +x /usr/local/bin/sonic-annotator && \
    cd / && rm -rf /tmp/sonic-annotator-1.7 /tmp/meson

# Set working directory
WORKDIR /app

# Copy dependency files first for better Docker layer caching
COPY Gemfile Gemfile.lock ./

# Install Ruby gems
RUN bundle config set --local deployment 'true' \
    && bundle config set --local without 'development test' \
    && bundle install

# Copy application files
COPY . .

# Make scripts executable
RUN chmod +x bin/prosodic-text-converter

# Create necessary directories
RUN mkdir -p spectrograms output transforms

# Note: Transform files are now generated automatically by the Ruby application

# ================================
# Final Production Stage
# ================================
FROM ruby:3.4.3 AS production

# Install only runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Audio processing runtime
    sox \
    imagemagick \
    aubio-tools \
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
    qt6-base-runtime \
    libglib2.0-0 \
    # Cleanup
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN groupadd -r prosodic && useradd -r -g prosodic prosodic

# Set working directory
WORKDIR /app

# Copy installed gems from builder stage
COPY --from=builder /usr/local/bundle /usr/local/bundle

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

# Expose volume for input files, output files, and spectrograms
VOLUME ["/app/input", "/app/output", "/app/spectrograms"]

# Set environment variables
ENV PROSODIC_PITCH_BACKEND=aubio
ENV BUNDLE_DEPLOYMENT=true
ENV BUNDLE_WITHOUT=development:test

# Health check to verify dependencies
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD ruby bin/prosodic-text-converter --health-check || exit 1

# Set entrypoint to the main application script
ENTRYPOINT ["ruby", "bin/prosodic-text-converter"]

# Default command shows help
CMD ["--help"]