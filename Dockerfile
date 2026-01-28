# Use official lightweight nginx image
FROM nginx:alpine

# Remove default nginx welcome page
RUN rm -rf /usr/share/nginx/html/*

# Copy all your static files into nginx's default html directory
COPY . /usr/share/nginx/html

# Expose port 80 (inside container)
EXPOSE 80

# Start nginx when container launches
CMD ["nginx", "-g", "daemon off;"]
