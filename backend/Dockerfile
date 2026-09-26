FROM python:3.11-slim

WORKDIR /app

# Copy requirements first (for better caching)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the application
COPY . .

# 1.12.3: bake the Firebase service-account key into the image so FCM push
# works with zero server setup. CI passes the key as a SINGLE-LINE base64
# blob in this build arg (multi-line JSON cannot travel through compose
# build-args — the value gets line-split and only "{" survives), then
# decodes and verifies it. Building without it (local dev, forks) simply
# skips this layer and the backend behaves exactly as before (ntfy/in-app
# notifications only). app.py auto-detects the file at /secrets/fcm.json and
# derives FCM_PROJECT_ID from its project_id field — a compose mount over
# /secrets/fcm.json or explicit env still overrides it.
ARG FCM_SERVICE_ACCOUNT_JSON_B64=""
RUN if [ -n "$FCM_SERVICE_ACCOUNT_JSON_B64" ]; then \
        mkdir -p /secrets && \
        printf '%s' "$FCM_SERVICE_ACCOUNT_JSON_B64" | base64 -d > /secrets/fcm.json && \
        python3 -c "import json;k=json.load(open('/secrets/fcm.json'));assert isinstance(k.get('client_email'),str) and k.get('private_key','').startswith('-----BEGIN'),'NOT a service-account key (missing client_email/private_key) - did you paste google-services.json instead of the key from Project settings > Service accounts?';print('fcm.json: valid service-account key for project',k.get('project_id','?'),'baked in')" && \
        chmod 600 /secrets/fcm.json; \
    else \
        echo "FCM_SERVICE_ACCOUNT_JSON_B64 not set — building WITHOUT the baked-in FCM key"; \
    fi

EXPOSE 8000

# Serve the real application (app.py), not the in-memory dev stub (main.py)
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
