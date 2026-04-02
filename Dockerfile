FROM alpine:latest

ARG GITHUB_TOKEN

RUN apk add --no-cache \
    bash git curl openssh nodejs npm screen nano

RUN ssh-keygen -A && \
    echo 'root:SecurePass123' | chpasswd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

RUN mkdir -p /bot /automator

# Clone and install bot
RUN if [ -n "$GITHUB_TOKEN" ]; then \
        git clone https://${GITHUB_TOKEN}@github.com/sdrelay/Relay.git /bot; \
    else \
        git clone https://github.com/sdrelay/Relay.git /bot; \
    fi
WORKDIR /bot
RUN npm install && npm update --save || true

# Clone, install, and BUILD automator
WORKDIR /
RUN if [ -n "$GITHUB_TOKEN" ]; then \
        git clone https://${GITHUB_TOKEN}@github.com/sdrelay/automator.git /automator; \
    else \
        git clone https://github.com/sdrelay/automator.git /automator; \
    fi

WORKDIR /automator
RUN npm install && npm update --save || true
RUN npm run build

# Copy startup script
COPY start_services.sh /start_services.sh
RUN chmod +x /start_services.sh

EXPOSE 10000 22

CMD ["/start_services.sh"]
