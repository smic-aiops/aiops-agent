ARG HORILLA_VERSION=1.5.0

FROM python:3.10-slim-bullseye AS builder

ENV PYTHONUNBUFFERED=1

RUN apt-get update \
  && apt-get install -y --no-install-recommends libcairo2-dev gcc \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app/

COPY source/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.10-slim-bullseye AS runtime

ENV PYTHONUNBUFFERED=1
ENV HORILLA_VERSION=${HORILLA_VERSION}

WORKDIR /app/

COPY --from=builder /install /usr/local
COPY source/ /app/

RUN chmod +x /app/entrypoint.sh

EXPOSE 8000

CMD ["sh", "./entrypoint.sh"]

