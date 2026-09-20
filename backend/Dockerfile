FROM python:3.11-slim

WORKDIR /app

# Copy requirements first (for better caching)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the application
COPY . .

EXPOSE 8000

# Serve the real application (app.py), not the in-memory dev stub (main.py)
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
