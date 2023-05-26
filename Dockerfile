#FROM perl:5.36
FROM szabgab/playground:latest
WORKDIR /opt
COPY Makefile.PL .
RUN cpanm --verbose --notest --installdeps .

