# Use Node 20 Bullseye (Debian) for OCR compatibility
FROM node:20-bullseye

# Install system dependencies for OCR, SSH, and Nginx
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
    nginx \
    && rm -rf /var/lib/apt/lists/*

# Setup SSH
RUN mkdir /var/run/sshd && \
    echo 'root:SecurePass123' | chpasswd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    ssh-keygen -A

# Setup Nginx Proxy
COPY nginx.conf /etc/nginx/sites-available/default

# Build argument for private repo
ARG GITHUB_TOKEN
ARG TURSO_DATABASE_URL
ARG TURSO_AUTH_TOKEN
ARG DASHBOARD_PASSWORD
ENV DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD
ENV TURSO_DATABASE_URL=$TURSO_DATABASE_URL
ENV TURSO_AUTH_TOKEN=$TURSO_AUTH_TOKEN
# Setup Bot
WORKDIR /bot
RUN if [ -n "$GITHUB_TOKEN" ]; then \
    git clone https://${GITHUB_TOKEN}@github.com/sdrelay/Relay.git . ; \
    else \
    git clone https://github.com/sdrelay/Relay.git . ; \
    fi && \
    npm install

# Setup Automator
WORKDIR /automator
RUN if [ -n "$GITHUB_TOKEN" ]; then \
    git clone https://${GITHUB_TOKEN}@github.com/sdrelay/automator.git . ; \
    else \
    git clone https://github.com/sdrelay/automator.git . ; \
    fi && \
    npm install && \
    npm run build

# Set environment to production
ENV NODE_ENV=production

# Startup script
COPY start_services.sh /start_services.sh
RUN chmod +x /start_services.sh

# Expose Render's port and SSH
EXPOSE 10000 22

CMD ["/start_services.sh"]
