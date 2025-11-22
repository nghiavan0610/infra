#!/bin/bash

# Install Docker for Amazon Linux
sudo yum update -y
sudo amazon-linux-extras enable docker
sudo yum install -y docker

# Start Docker
sudo systemctl start docker
sudo systemctl enable docker

# Add current user to docker group (optional)
sudo usermod -aG docker $USER

# Install Docker Compose (v2)
DOCKER_COMPOSE_VERSION="v2.38.2"
ARCH=$(uname -m)
sudo curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-${ARCH}" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Check versions
docker -v
docker-compose -v
