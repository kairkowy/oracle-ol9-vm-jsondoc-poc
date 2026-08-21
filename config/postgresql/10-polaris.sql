-- Run as postgres after replacing the password placeholder.
CREATE ROLE polaris LOGIN PASSWORD 'CHANGE_ME_POSTGRES_SECRET';
CREATE DATABASE polaris OWNER polaris ENCODING 'UTF8';
