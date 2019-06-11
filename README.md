# PostgresApp

PostgresApp, expertimental elixir application to import export data
from Postgres tables.

1e6 records are put into the source table using COPY command. The pool of
connections speeds up the insert operation.

Later the recored from source table are copied into the dest table through:
  1. Stream the source table data to a file.
  2. Stream the file data to dest table.

Both the above operations are done using COPY command.

User can also stream all the records in CSV format through the rest endpoints:
  - GET /dbs/foo/tables/source
  - GET /dbs/bar/tables/dest
HTTP chunked encoding is used to stream the CSV to the user.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `postgres_app` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:postgres_app, "~> 0.1.0"}
  ]
end
```

## Environment details:
  elixir: 1.8
  erlang otp: 21

## Steps to follow:
  1. Make sure your postgres server is running.
  2. Change the configurations username, password and hostname according to your
     postgres server details. Config file: postgres_app/config/config.exs
  3. Get the dependencies ```mix deps.get```
  4. Compile the dependencies ```mix deps.compile```
  6. Create a database `foo` and `bar` in your Postgres server.
  8. Start the app - `iex -S mix`, the app listens for http request on `localhost:4000`
  9. Fill the source table:
    ```elixir
    :iex> PostgresApp.fill_source()
    ```
  10. Fill the dest table:
    ```elixir
    :iex> PostgresApp.fill_dest()
    ```
  11. Stream data from source table from terminal:
    - `curl -vv 'http://localhost:4000/dbs/foo/tables/source' -X GET`
    - `curl -vv 'http://localhost:4000/dbs/bar/tables/dest' -X GET`
