FROM arizephoenix/phoenix:latest

# Phoenix's venv is managed by uv — use uv to add packages so it
# doesn't touch or corrupt the existing dependency tree.
RUN uv pip install --python /phoenix/.venv --no-cache sqlalchemy-cockroachdb
