defmodule Ghoul.Worker.Supervisor do
  @moduledoc false

  @doc "Ghoul.Worker"
  use DynamicSupervisor

  #############
  # API
  #############

  def start_link([]), do: DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)

  def start_child(process_key, pid, callback, initial_state) do
    spec = %{
      id: {Ghoul.Worker, process_key, pid, callback, initial_state},
      start: {Ghoul.Worker, :start_link, [process_key, pid, callback, initial_state]},
      restart: :transient
    }
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  ##############################
  # GenServer Callbacks
  ##############################

  @impl DynamicSupervisor
  def init([]), do: DynamicSupervisor.init(strategy: :one_for_one)

  ##############################
  # Internal
  ##############################

end
