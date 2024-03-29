defmodule PostgresApp.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {PostgresApp, []},
      Plug.Cowboy.child_spec(scheme: :http, plug: PostgresApp.Router, options: [port: 4000])
    ]

    opts = [strategy: :one_for_one, name: PostgresApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
