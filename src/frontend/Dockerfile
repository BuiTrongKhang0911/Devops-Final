# Build stage
FROM node:20-alpine AS builder

WORKDIR /app

COPY package.json ./
RUN npm install

COPY . .
RUN npm run build

# Production stage
FROM nginx:alpine

# Update Alpine packages to fix CVEs (zlib, etc.)
RUN apk upgrade --no-cache

COPY --from=builder /app/dist /usr/share/nginx/html

# Copy nginx config from source file
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
