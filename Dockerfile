# Use Debian-based Node image for full compatibility with ddddocr-node
FROM node:20-bullseye

# Install system dependencies for OCR, SSH, and build tools
RUN apt-get update && apt-get install -y \
    libgomp1 \
    libgl1-mesa-glx \
    libglib2.0-0 \
    python3 \
    make \
    g++ \
    bash \
    git \
    curl \
    openssh-server \
    screen \
    nano \
    && rm -rf /var/lib/apt/lists/*

# Setup SSH Server
RUN mkdir /var/run/sshd && \
    echo 'root:SecurePass123' | chpasswd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    ssh-keygen -A

# Create working directories
RUN mkdir -p /bot /automator

# Build argument for private repo access
ARG GITHUB_TOKEN

# Clone and install the Bot
WORKDIR /bot
RUN if [ -n "$GITHUB_TOKEN" ]; then \
    git clone https://${GITHUB_TOKEN}@github.com/sdrelay/Relay.git . ; \
    else \
    git clone https://github.com/sdrelay/Relay.git . ; \
    fi && \
    npm install && npm update --save || true

# Clone, install, and BUILD the Automator
WORKDIR /automator
RUN if [ -n "$GITHUB_TOKEN" ]; then \
    git clone https://${GITHUB_TOKEN}@github.com/sdrelay/automator.git . ; \
    else \
    git clone https://github.com/sdrelay/automator.git . ; \
    fi && \
    npm install && npm update --save || true && \
    npm run build

# Copy and setup the startup script
# Ensure you have a 'start_services.sh' file in your project root
COPY start_services.sh /start_services.sh
RUN chmod +x /start_services.sh

# Expose the app port (Render default is often 10000) and SSH
EXPOSE 10000 22

CMD ["/start_services.sh"]
