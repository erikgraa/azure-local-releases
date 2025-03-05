# Pull down Pode image
FROM badgerati/pode:latest

# Copy local files to the container
COPY ./pode/* /usr/src/app/
COPY ./scripts/Get-AzureLocalRelease.ps1 /usr/src/app/

# Expose port
EXPOSE 8080

# Run Pode
CMD [ "pwsh", "-WorkingDirectory", "/usr/src/app", "-Command", "./server.ps1" ]