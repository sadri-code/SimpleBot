FROM alpine:latest

# Install system dependencies (screen is already included)
RUN apk add --no-cache \
    bash \
    git \
    curl \
    openssh \
    nodejs \
    npm \
    screen \
    nano

# Configure SSH
RUN ssh-keygen -A && \
    echo 'root:SecurePass123' | chpasswd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Create working directories
RUN mkdir -p /app /bot

# Clone the bot repository during build
RUN git clone https://github.com/sdrelay/Relay.git /bot

# Install bot dependencies
WORKDIR /bot
RUN npm install

# Copy your web application (if any)
WORKDIR /
COPY app/ /app

# Copy and install dependencies for the web server (if package.json exists in root)
COPY package*.json ./
RUN npm install

# Copy the startup script
COPY start_services.sh /start_services.sh
RUN chmod +x /start_services.sh

# Expose ports (web and SSH)
EXPOSE 10000 22

CMD ["/start_services.sh"]
