# The bot's image (chapter 10). Built by Coolify from your bot's repository, or by `docker compose build`.
FROM python:3.12-slim
RUN useradd --uid 1000 --create-home bot && mkdir /data && chown bot /data
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY bot/ ./bot/
USER bot
EXPOSE 9090
# Healthy while the dashboard message was edited in the last three refreshes. While it starts, Docker asks every
# 5 seconds, so Coolify sees it healthy soon after a deploy.
HEALTHCHECK --interval=60s --timeout=5s --start-period=30s --start-interval=5s --retries=2 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:9090/health', timeout=3).status == 200 else 1)"
CMD ["python", "-m", "bot"]
