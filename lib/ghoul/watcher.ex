defmodule Ghoul.Watcher do
  use GenServer
  import ShorterMaps
  ##############################
  # API
  ##############################

  def start_link() do
    GenServer.start_link(__MODULE__, [], [name: __MODULE__])
  end

  def summon(pid, process_key, callback, initial_state) do
    GenServer.call(__MODULE__, {:summon, pid, process_key, callback, initial_state})
  end

  def banish(process_key) do
    GenServer.call(__MODULE__, {:banish, process_key})
  end

  defmodule State do
    @doc false
    defstruct [
      pending: %{},
    ]
  end

  ##############################
  # GenServer Callbacks
  ##############################

  def init([]) do
    {:ok, %State{}}
  end

  def handle_call({:summon, pid, process_key, callback, initial_state}, from, ~M{pending} = state) do
    request = ~M{pid, process_key, callback, initial_state, from}
    case Ghoul.Worker.get_worker_for(process_key) do
      {:ok, worker_pid} ->
        worker_ref = Process.monitor(worker_pid)
        pending = Map.put(pending, worker_ref, request)
        {:noreply, ~M{state|pending}}
      {:error, :no_process} ->
        do_summon(request)
        {:reply, :ok, state}
    end
  end

  def handle_call({:banish, process_key}, _from, state) do
    result = case Ghoul.Worker.get_worker_for(process_key) do
      {:ok, worker_pid} ->
        Ghoul.Worker.stop(worker_pid)
        :ok
      error -> error
    end
    {:reply, result, state}
  end

  def handle_info({:DOWN, monitor_ref, :process, _pid, _reason}, ~M{pending} = state) do
    {~M{from} = request, pending} = Map.pop(pending, monitor_ref)
    do_summon(request)
    GenServer.reply(from, :ok)
    {:noreply, ~M{state|pending}}
  end

  ##############################
  # Internal Calls
  ##############################

  def do_summon(~M{pid, process_key, callback, initial_state}) do
    Ghoul.Worker.create(pid, process_key, callback, initial_state)
  end

end
