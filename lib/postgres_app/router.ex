defmodule PostgresApp.Router do
  use Plug.Router
  plug :match
  plug :dispatch

  @source_conn Application.get_env(:postgres_app, :source_db)[:name]
  @dest_conn Application.get_env(:postgres_app, :dest_db)[:name]
  @source_table Application.get_env(:postgres_app, :source_table)
  @dest_table Application.get_env(:postgres_app, :dest_table)

  get "/hello" do
    send_resp(conn, 200, "world")
  end

  get "/dbs/foo/tables/source" do
    export_data(conn, @source_conn, @source_table)
  end

  get "/dbs/bar/tables/dest" do
    export_data(conn, @dest_conn, @dest_table)
  end

  match _ do
    send_resp(conn, 404, "oops")
  end

  def export_data(conn, db_conn, table) do
    conn =
      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header("content-disposition", ~s[attachment; filename="source.csv"])
      |> send_chunked(:ok)

    columns = ~w(a b c)
    csv_header = [Enum.join(columns, ","), "\n"]

    PostgresApp.with_stream(fn stream ->
        stream
        |> Stream.map(&(&1.rows))
        |> (fn stream -> Stream.concat(csv_header, stream) end).() # Construct CSV
        |> Enum.reduce_while(conn, fn (data, conn) -> # Send chunked response
             case chunk(conn, data) do
               {:ok, conn} ->
                 {:cont, conn}
               {:error, :closed} ->
                 {:halt, conn}
             end
           end)
      end,
      db_conn,
      table)

    conn
  end

end
