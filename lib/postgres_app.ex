defmodule PostgresApp do
  @moduledoc """
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
  """

  use GenServer
  @gen_server_name :postgrex_app_server
  @default_timeout :timer.minutes(5)
  @dump_path "./source_table_dump"

  @doc """
  Hello world.

  ## Examples

      iex> PostgresApp.hello()
      :world

  """
  def hello do
    :world
  end

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: @gen_server_name)
  end

  def init(_state) do
    # Open named connection with source database.
    {:ok, _pid} =
      Application.get_env(:postgres_app, :source_db)
      |> Postgrex.start_link()

    source_conn = get_conn_name(:source_db)
    source_table = Application.get_env(:postgres_app, :source_table)

    # Open named connection with dest database.
    {:ok, _pid} =
      Application.get_env(:postgres_app, :dest_db)
      |> Postgrex.start_link()

    dest_conn = get_conn_name(:dest_db)
    dest_table = Application.get_env(:postgres_app, :dest_table)

    state = %{
      source_conn: source_conn,
      source_table: source_table,
      dest_conn: dest_conn,
      dest_table: dest_table
    }
    {:ok, state}
  end

  @doc """
  fill_source/0: Fills the source table in foo database with 1e6 records.
  The records are put using COPY command, also a pool of workers is used
  to speed up the insertion process.

  ## Examples:
      iex> PostgresApp.fill_source()
      :ok
  """
  @spec fill_source() :: :ok
  def fill_source() do
    GenServer.call(@gen_server_name, :fill_source, @default_timeout)
  end

  @doc """
  fill_dest/0: Fills the dest table in foo database with 1e6 records.
  The records from the source table are dumped to a file using copy command.
  The file contents are then copied into dest table.

  COPY command is used inside Postgrex.stream/3 along with pool of workers.

  ## Examples:
      iex> PostgresApp.fill_dest()
      :ok
  """
  @spec fill_dest() :: :ok
  def fill_dest() do
    GenServer.call(@gen_server_name, :fill_dest, 2 * @default_timeout)
  end

  @doc """
  with_stream/3: Takes a function, db_connection, table_name as input.

  Postgrex stream is formed to stream the table contents over HTTP chunked encoding.
  callback here is the function which is executed upon the stream for further
  processing such as conversion of stream to CSV and sending chunked response.
  """
  def with_stream(callback, db_conn, table) do

    Postgrex.transaction(db_conn, fn conn ->
        stream = Postgrex.stream(conn, "COPY (SELECT a, b, c FROM #{table}) TO STDOUT WITH CSV DELIMITER ','", []) #
        callback.(stream)
      end,
      [pool: DBConnection.Poolboy,
      pool_timeout: :infinity,
      timeout: :infinity]
    )

  end

  #
  # Get the name of db_conn
  #
  defp get_conn_name(db) do
    Application.get_env(:postgres_app, db)[:name]
  end

  #
  # Get the record.
  #
  defp get_record(x) do
    ["#{x}", ?\t, "#{rem(x, 3)}", ?\t, "#{rem(x, 5)}", ?\n]
  end

  def handle_call(:fill_source, _from, state) do
    %{source_conn: source_conn, source_table: source_table} = state

    Postgrex.query(source_conn, "CREATE TABLE IF NOT EXISTS #{source_table}(a int, b int, c int)", [])

    Postgrex.transaction(source_conn, fn conn ->
        copy = Postgrex.stream(conn, "COPY #{source_table}(a, b, c) FROM STDIN", [])

        1..1_000_000
        |> Enum.map(fn x -> get_record(x) end)
        |> Enum.into(copy)

      end,
      [pool: DBConnection.Poolboy,
      pool_timeout: :infinity,
      timeout: :infinity]
    )

    {:reply, :ok, state}
  end

  def handle_call(:fill_dest, _from, state) do
    %{source_conn: source_conn, source_table: source_table, dest_conn: dest_conn, dest_table: dest_table} = state

    Postgrex.query(dest_conn, "CREATE TABLE IF NOT EXISTS #{dest_table}(a int, b int, c int)", [])

    # Copy source table contents to a file.
    Postgrex.transaction(source_conn, fn conn ->
        copy = Postgrex.stream(conn, "COPY (SELECT a, b, c FROM #{source_table}) TO STDOUT", [])

        copy
        |> Enum.map(fn %Postgrex.Result{rows: rows} -> rows end)
        |> Enum.into(File.stream!(@dump_path))
      end,
      [pool: DBConnection.Poolboy,
      pool_timeout: :infinity,
      timeout: :infinity]
    )

    # Copy the contents from file to dest table
    Postgrex.transaction(dest_conn, fn conn ->
        copy = Postgrex.stream(conn, "COPY #{dest_table}(a, b, c) FROM STDIN", [])

        File.stream!(@dump_path)
        |> Enum.map(fn line ->
          [a, b, c] = line |> String.trim |> String.split("\t", trim: true, parts: 3)
          [a, ?\t, b, ?\t, c, ?\n]
        end)
        |> Enum.into(copy)

      end,
      [pool: DBConnection.Poolboy,
      pool_timeout: :infinity,
      timeout: :infinity]
    )

    {:reply, :ok, state}
  end

end
