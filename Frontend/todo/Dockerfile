# ---------- Stage 1: build ----------
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi
COPY . .
RUN npm run build

# ---------- Stage 2: runtime (nginx, non-root) ----------
FROM nginxinc/nginx-unprivileged:1.27-alpine
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /app/build /usr/share/nginx/html
ENV BACKEND_URL=http://todo-backend:8080
EXPOSE 8080