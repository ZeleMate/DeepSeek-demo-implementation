# DVMCP's four challenges in our attack set (#59), built by labs/dvmcp/build.sh. Upstream's own
# Dockerfile runs fifteen servers and a dashboard under supervisord as root; this image holds only
# the four servers, our stdio entry point and their locked dependencies, and runs as nobody.
# Bump a digest only with its tag comment; Dependabot's docker entry tracks both.
FROM ghcr.io/astral-sh/uv:0.13.3@sha256:bee0a2a458fd956c5df7b8b4c5fed2257b0af34866e3da7b51db0be3acb375d1 AS uv

FROM python:3.13-slim@sha256:168d3a5d10f2152f8e8d77b6843ac82c22a846cfefeef7afdf9aa630404e82a7

WORKDIR /lab
# Installed from uv.lock with its hashes; --frozen fails instead of re-resolving, and --no-build
# takes wheels only, so no package's setup script runs during the build.
COPY pyproject.toml uv.lock ./
RUN --mount=from=uv,source=/uv,target=/bin/uv \
    UV_PROJECT_ENVIRONMENT=/lab/.venv uv sync --frozen --no-build --no-dev --no-install-project --no-cache

# The challenge files, fetched at the pinned commit and checked against challenges.sha256.
COPY challenges/ ./challenges/
COPY serve.py ./

# nobody:nogroup. The container runs with a read-only root and a tmpfs /tmp, where challenge 3
# writes its seed files (bundles/redteam/bundle.patch.yml).
USER 65534:65534
ENV PATH=/lab/.venv/bin:$PATH PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
ENTRYPOINT ["python", "/lab/serve.py"]
