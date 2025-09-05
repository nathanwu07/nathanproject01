# syntax=docker/dockerfile:1.7
FROM node:20-alpine AS base
WORKDIR /app
COPY app/package.json ./
RUN npm install --omit=dev
COPY app ./
EXPOSE 3000
ENV NODE_ENV=production
CMD ["node", "server.js"]


