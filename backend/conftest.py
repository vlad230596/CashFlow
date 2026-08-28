import os

# Pytest imports application modules during collection. Set the database before
# `main` can initialize Flask-SQLAlchemy so tests can never bind to local or
# production data, regardless of module import order.
os.environ['CASHFLOW_DATABASE_URL'] = 'sqlite://'
os.environ['CASHFLOW_ENVIRONMENT'] = 'test'
