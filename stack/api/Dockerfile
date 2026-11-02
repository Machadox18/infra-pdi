FROM python:3.12-slim

# Valores padrão: podem ser sobrescritos no docker run ou no compose
ENV PORT=8000 \
    APP_MESSAGE="mensagem padrao" \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY app.py .

# Nunca rode como root dentro do container
RUN useradd --create-home appuser
USER appuser

EXPOSE 8000
HEALTHCHECK --interval=15s CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/')"
CMD ["python", "app.py"]