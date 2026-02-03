# Dockerfile for n8n on Fly
FROM n8nio/n8n:latest

# Workdir is already set in the base image, but keeping it explicit
WORKDIR /home/node

# Ensure persistent storage dir exists and owned by node (image usually handles this)
RUN mkdir -p /home/node/.n8n && chown -R node:node /home/node/.n8n

USER node

EXPOSE 5678

# The base image includes the entrypoint and CMD that start n8n
