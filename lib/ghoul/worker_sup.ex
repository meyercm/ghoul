defmodule Ghoul.Worker.Supervisor do
  use Supervisor

  #############
  # API
  #############

  def start_link do
    Supervisor.start_link(__MODULE__, [], [name: __MODULE__])
  end

  def start_child(process_key, pid, callback, initial_state) do
    Supervisor.start_child(__MODULE__, [process_key, pid, callback, initial_state])
  end

  ##############################
  # GenServer Callbacks
  ##############################

  def init([]) do
    children = [
      worker(Ghoul.Worker, [], restart: :transient)
    ]
    supervise(children, strategy: :simple_one_for_one)
  end

  ##############################
  # Internal
  ##############################

end
