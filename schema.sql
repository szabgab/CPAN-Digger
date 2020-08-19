CREATE TABLE dists (
    distribution VARCHAR(255) NOT NULL UNIQUE,
    version      VARCHAR(255),
    author       VARCHAR(255),
    vcs_url      VARCHAR(255),
    vcs_name     VARCHAR(255),
    travis       BOOLEAN
);
