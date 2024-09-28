VERSION 0.6

all:
    ARG ELIXIR_BASE=1.15.6-erlang-25.3.2.6-alpine-3.18.4
    BUILD \
        --build-arg POSTGRES=16.2-alpine \
        --build-arg POSTGRES=11.11-alpine \
        --build-arg POSTGRES=9.6-alpine \
        --build-arg POSTGRES=9.5-alpine \
        +integration-test-postgres

    BUILD \
        --build-arg MYSQL=5.7 \
        --build-arg MYSQL=8.0 \
        +integration-test-mysql

    BUILD \
        --build-arg MSSQL=2017 \
        --build-arg MSSQL=2019 \
        +integration-test-mssql

setup-base:
    ARG ELIXIR_BASE=1.15.6-erlang-25.3.2.6-alpine-3.18.4
    FROM hexpm/elixir:$ELIXIR_BASE
    RUN apk add --no-progress --update git build-base
    ENV ELIXIR_ASSERT_TIMEOUT=10000
    WORKDIR /src/ecto_sql
    RUN apk add --no-progress --update docker docker-compose
    RUN mix local.rebar --force
    RUN mix local.hex --force

COMMON_SETUP_AND_MIX:
    COMMAND
    COPY mix.exs mix.lock .formatter.exs .
    COPY --dir bench integration_test lib test ./
    RUN mix deps.get
    RUN mix deps.compile
    RUN mix compile #--warnings-as-errors

integration-test-postgres:
    FROM +setup-base
    ARG POSTGRES="11.11"

    IF [ "$POSTGRES" = "9.5-alpine" ]
        # for 9.5 we require a downgraded version of pg_dump;
        # and in the 3.4 version, it is not included in postgresql-client but rather in postgresql
        RUN echo 'http://dl-cdn.alpinelinux.org/alpine/v3.4/main' >> /etc/apk/repositories
        RUN apk add postgresql=9.5.13-r0
    ELSE IF [ "$POSTGRES" = "16.2-alpine" ]
        # for 16 we need an upgraded version of pg_dump;
        # alpine 3.16 does not come with the postgres 16 client by default;
        # we must first update the public keys for the packages because they
        # might have been rotated since our image was built
        RUN apk add -X https://dl-cdn.alpinelinux.org/alpine/v3.19/main -u alpine-keys
        RUN echo 'http://dl-cdn.alpinelinux.org/alpine/v3.19/main' >> /etc/apk/repositories
        RUN apk add postgresql16-client
    ELSE
        RUN apk add postgresql-client
    END

    DO +COMMON_SETUP_AND_MIX

    # then run the tests
    WITH DOCKER \
        --pull "postgres:$POSTGRES" --platform linux/amd64
        RUN set -e; \
            timeout=$(expr $(date +%s) + 30); \
            docker run --name pg --network=host -d -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=postgres "postgres:$POSTGRES"; \
            # wait for postgres to start
            while ! pg_isready --host=127.0.0.1 --port=5432 --quiet; do \
                test "$(date +%s)" -le "$timeout" || (echo "timed out waiting for postgres"; exit 1); \
                echo "waiting for postgres"; \
                sleep 1; \
            done; \
            # run tests
            PG_URL=postgres:postgres@127.0.0.1 ECTO_ADAPTER=pg mix test;
    END

integration-test-mysql:
    FROM +setup-base
    RUN apk add mysql-client

    DO +COMMON_SETUP_AND_MIX

    ARG MYSQL="5.7"
    WITH DOCKER \
        --pull "mysql:$MYSQL" --platform linux/amd64
        RUN set -e; \
            timeout=$(expr $(date +%s) + 30); \
            docker run --name mysql --network=host -d -e MYSQL_ROOT_PASSWORD=root "mysql:$MYSQL" \
            --sql_mode="ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION,ANSI_QUOTES" \
            # the default authentication plugin for MySQL 8 is sha 256 but it doesn't come with the docker image. falling back to the 5.7 way
            --default-authentication-plugin=mysql_native_password; \
            # wait for mysql to start
            while ! mysqladmin ping --host=127.0.0.1 --port=3306 --protocol=TCP --silent; do \
                test "$(date +%s)" -le "$timeout" || (echo "timed out waiting for mysql"; exit 1); \
                echo "waiting for mysql"; \
                sleep 1; \
            done; \
            # run tests
            MYSQL_URL=root:root@127.0.0.1 ECTO_ADAPTER=myxql mix test;
    END


integration-test-mssql:
    ARG TARGETARCH
    FROM +setup-base

    RUN apk add --no-cache curl gnupg --virtual .build-dependencies -- && \
        curl -O https://download.microsoft.com/download/3/5/5/355d7943-a338-41a7-858d-53b259ea33f5/msodbcsql18_18.3.2.1-1_${TARGETARCH}.apk && \
        curl -O https://download.microsoft.com/download/3/5/5/355d7943-a338-41a7-858d-53b259ea33f5/mssql-tools18_18.3.1.1-1_${TARGETARCH}.apk && \
        echo y | apk add --allow-untrusted msodbcsql18_18.3.2.1-1_${TARGETARCH}.apk mssql-tools18_18.3.1.1-1_${TARGETARCH}.apk && \
        apk del .build-dependencies && rm -f msodbcsql*.sig mssql-tools*.apk
    ENV PATH="/opt/mssql-tools18/bin:${PATH}"

    DO +COMMON_SETUP_AND_MIX

    ARG MSSQL="2017"
    WITH DOCKER \
        --pull "mcr.microsoft.com/mssql/server:$MSSQL-latest" --platform linux/amd64
        RUN set -e; \
            timeout=$(expr $(date +%s) + 30); \
            docker run -d -p 1433:1433 --name mssql -e 'ACCEPT_EULA=Y' -e 'MSSQL_SA_PASSWORD=some!Password' "mcr.microsoft.com/mssql/server:$MSSQL-latest"; \
            # wait for mssql to start
            while ! sqlcmd -C -S tcp:127.0.0.1,1433 -U sa -P 'some!Password' -Q "SELECT 1" >/dev/null 2>&1; do \
                test "$(date +%s)" -le "$timeout" || (echo "timed out waiting for mssql"; exit 1); \
                echo "waiting for mssql"; \
                sleep 1; \
            done; \
            # run tests
            ECTO_ADAPTER=tds mix test;
    END
