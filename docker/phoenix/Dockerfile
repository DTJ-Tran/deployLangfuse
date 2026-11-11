FROM arizephoenix/phoenix:latest

# Install CockroachDB SQLAlchemy dialect into Phoenix's own venv
RUN python -m venv /phoenix/.venv && /phoenix/.venv/bin/pip install --no-cache-dir sqlalchemy-cockroachdb