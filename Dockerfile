# Base Jenkins image
FROM jenkins/jenkins:lts

# Switch to root to install tools
USER root

# Install Docker, Ansible, SSH
RUN apt update && \
    apt install -y docker.io ansible sshpass && \
    usermod -aG docker jenkins

# Return to Jenkins user
USER jenkins