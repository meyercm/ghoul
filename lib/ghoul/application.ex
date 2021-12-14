defmodule Ghoul.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do

    # Define workers and child supervisors to be supervised
    children = [
      Ghoul.Worker.Supervisor.child_spec([]),
      Ghoul.Watcher.child_spec([])
    ]

    opts = [strategy: :one_for_one, name: Ghoul.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
