FROM nginx:alpine

# Version of the app, baked in at build time and shown in the sidebar
# (frontend reads /version.txt with cache: no-store, so it always reflects
# what the server is actually serving).
COPY VERSION /usr/share/nginx/html/version.txt

# Copy the nginx configuration file
COPY nginx.conf /etc/nginx/nginx.conf

# Copy application files to the container
COPY . /usr/share/nginx/html/

# Expose port 80 for nginx
EXPOSE 80

# Start nginx in the foreground
CMD ["nginx", "-g", "daemon off;"]
