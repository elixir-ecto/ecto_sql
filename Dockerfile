FROM hexpm/elixir:1.10.4-erlang-23.0.3-ubuntu-bionic-20200630

# RUN apt-get update
# RUN apt-get install -y curl gnupg
# RUN curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add -
# RUN curl https://packages.microsoft.com/config/ubuntu/16.04/prod.list | tee /etc/apt/sources.list.d/msprod.list
# RUN apt-get update
# ENV ACCEPT_EULA Y
# RUN apt-get install -y mssql-tools unixodbc-dev

RUN apt-get update
RUN apt-get install -y curl gnupg
RUN curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
RUN echo "deb http://apt.postgresql.org/pub/repos/apt/ bionic-pgdg main 9.5" >> /etc/apt/sources.list.d/pgdg.list
RUN apt-get update
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get install -y postgresql-9.5 postgresql-contrib-9.5
RUN psql --version
