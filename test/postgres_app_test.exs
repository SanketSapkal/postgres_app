defmodule PostgresAppTest do
  use ExUnit.Case
  doctest PostgresApp

  test "greets the world" do
    assert PostgresApp.hello() == :world
  end
end
