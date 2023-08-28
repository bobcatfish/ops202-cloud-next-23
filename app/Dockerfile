# multi-stage build
FROM python:3.10.12-alpine3.18 AS build

# install dependencies in a venv
RUN python -m venv /home/nonroot/venv
ENV PATH="/home/nonroot/venv/bin:$PATH"
WORKDIR /home/nonroot
COPY . /home/nonroot
RUN apk add build-base linux-headers
RUN pip install -r requirements.txt

# run image
FROM python:3.10.12-alpine3.18

RUN addgroup -S nonroot && adduser -S nonroot -G nonroot -u 65532
USER 65532
WORKDIR /home/nonroot
COPY --chown=nonroot:nonroot --from=build /home/nonroot /home/nonroot

# run container as nonroot user
ENV PATH="/home/nonroot/venv/bin:$PATH"
ENV PORT 8080
ENV GUNICORN_CMD_ARGS="--workers 2 --threads 4 -b 0.0.0.0:8080 --chdir /home/nonroot"

# Run the web service on container startup.
ENTRYPOINT [ "gunicorn", "app:app" ]
