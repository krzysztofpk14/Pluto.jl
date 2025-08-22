FROM julia:1.11.3

# Install system dependencies including kubectl
RUN apt-get update && apt-get install -y \
    git \
    curl \
    net-tools \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    && curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/ \
    && rm -rf /var/lib/apt/lists/*

# Create pluto user
RUN useradd --create-home --shell /bin/bash --user-group pluto
USER pluto
WORKDIR /home/pluto

# Copy and install Julia dependencies
COPY --chown=pluto:pluto Project.toml Manifest.toml ./
# Copy application code
COPY --chown=pluto:pluto . .
RUN julia --project=@. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'


# Expose port
EXPOSE 8080

# Environment variables
ENV PLUTO_HOST=0.0.0.0
ENV PLUTO_PORT=8080

# Simple start command
CMD ["julia", "--project=@.", "--color=yes", "start_pluto.jl"]