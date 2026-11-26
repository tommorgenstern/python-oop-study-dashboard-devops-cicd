FROM python:3.11-slim

# Environment variables for Python and pip
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=8000

# Create non-root user
RUN useradd -m -u 10001 appuser

WORKDIR /app

# Install dependencies first for better caching
COPY --chown=appuser:appuser requirements.txt .
RUN pip install --upgrade pip && pip install -r requirements.txt

# Copy application code
COPY --chown=appuser:appuser . .

USER appuser

EXPOSE 8000
CMD ["gunicorn", "-w", "2", "-b", "0.0.0.0:8000", "wsgi:app"]
