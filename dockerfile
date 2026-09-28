FROM python:3.14.7-trixie AS base
WORKDIR /app

FROM base AS development
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    openssh-client \
    curl
RUN curl -fsSL -o /usr/local/bin/dbmate https://github.com/amacneil/dbmate/releases/latest/download/dbmate-linux-amd64 \
    && chmod +x /usr/local/bin/dbmate
COPY . .
CMD ["tail", "-f", "/dev/null"]