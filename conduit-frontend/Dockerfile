# syntax=docker/dockerfile:1

# =============================================================================
# Stage 1 - compile the Angular application.
#
# API_URL is a BUILD argument, not a runtime variable: Angular inlines it into
# the bundle. It must therefore be an address the end user's browser can reach
# (public host or IP) - never an internal Compose service name.
# =============================================================================
FROM node:20-alpine AS builder

ARG API_URL=http://localhost:8000/api
ENV API_URL=${API_URL}

WORKDIR /app

# Copy manifests first so the dependency layer is cached across source changes.
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

COPY . .

# `prebuild` runs scripts/set-env.js, which bakes API_URL into environment.ts.
RUN npm run build

# The output layout differs between Angular builders, so normalise it here:
# the `application` builder nests files under browser/, `browser-esbuild` does not.
RUN if [ -d dist/angular-conduit/browser ]; then \
        mv dist/angular-conduit/browser /app/out; \
    else \
        mv dist/angular-conduit /app/out; \
    fi

# =============================================================================
# Stage 2 - serve the static bundle. Only the compiled output ships; neither
# node_modules nor the Node runtime end up in the final image.
# =============================================================================
FROM nginx:1.27-alpine AS runtime

COPY --from=builder /app/out /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 8282

CMD ["nginx", "-g", "daemon off;"]
