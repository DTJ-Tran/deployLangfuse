FROM arizephoenix/phoenix:latest

# Install CockroachDB SQLAlchemy dialect into Phoenix's own venv
RUN /phoenix/.venv/bin/python -m ensurepip --upgrade && \
    /phoenix/.venv/bin/python -m pip install --no-cache-dir sqlalchemy-cockroachdb