# Stage 1: Dependencies (full install, includes Prisma CLI needed at runtime)
FROM node:20-alpine AS deps
WORKDIR /app
RUN apk add --no-cache libc6-compat openssl
# package.json comes from the app folder; yarn.lock is a real file kept at the
# project root (the copy inside nextjs_space is a platform-only symlink).
COPY nextjs_space/package.json ./package.json
COPY yarn.lock ./yarn.lock
RUN yarn install --frozen-lockfile

# Stage 2: Build
FROM node:20-alpine AS builder
WORKDIR /app
RUN apk add --no-cache libc6-compat openssl
COPY --from=deps /app/node_modules ./node_modules
COPY nextjs_space/ .
# Ensure a real lockfile is present in the build stage too (overwrites the
# platform symlink that ships inside nextjs_space).
COPY yarn.lock ./yarn.lock

# Generate Prisma client
RUN npx prisma generate

# Build the Next.js app
ENV NEXT_TELEMETRY_DISABLED=1
RUN yarn build

# Stage 3: Runner
FROM node:20-alpine AS runner
WORKDIR /app
RUN apk add --no-cache libc6-compat openssl

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

# Copy the built app together with its full dependency tree.
# The complete node_modules is kept so the Prisma CLI is available to
# sync the database schema on first start.
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/public ./public
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/next.config.js ./next.config.js

# Startup script: sync DB schema, then start the server
COPY docker-entrypoint.sh ./docker-entrypoint.sh
RUN chmod +x ./docker-entrypoint.sh && mkdir -p /mnt/nas/solray

EXPOSE 3000

ENTRYPOINT ["./docker-entrypoint.sh"]
