defmodule Ghoul.Watcher do
  @moduledoc false
  use GenServer
  import ShorterMaps
  ##############################
  # API
  ##############################

  def start_link do
    GenServer.start_link(__MODULE__, [], [name: __MODULE__])
  end

  @spec summon(pid, Ghoul.process_key, Ghoul.on_death_callback, any, non_neg_integer) :: :ok | {:error, atom}
  def summon(pid, process_key, callback, initial_state, timeout_ms) do
    GenServer.call(__MODULE__, {:summon, pid, process_key, callback, initial_state, timeout_ms}, timeout_ms + 200)
  end

  @spec banish(Ghoul.process_key) :: :ok | {:error, atom}
  def banish(process_key) do
    GenServer.call(__MODULE__, {:banish, process_key})
  end

  defmodule State do
    @moduledoc false
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

  def handle_call({:summon, pid, process_key, callback, initial_state, timeout_ms}, from, ~M{pending} = state) do
    request = ~M{pid, process_key, callback, initial_state, from}
    case Ghoul.Worker.get_worker_for(process_key) do
      {:ok, worker_pid} ->
        worker_ref = Process.monitor(worker_pid)
        timer_ref = Process.send_after(self(), {:summon_timeout, worker_ref}, timeout_ms)
        request = Map.put(request, :timer_ref, timer_ref)
        pending = Map.put(pending, worker_ref, request)
        {:noreply, ~M{state|pending}}
      {:error, :no_process} ->
        {:ok, _pid} = do_summon(request)
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
    {~M{from, timer_ref} = request, pending} = Map.pop(pending, monitor_ref)
    Process.cancel_timer(timer_ref)
    {:ok, _pid} = do_summon(request)
    GenServer.reply(from, :ok)
    {:noreply, ~M{state|pending}}
  end

  def handle_info({:summon_timeout, worker_ref}, ~M{pending} = state) do
    {request, pending} = Map.pop(pending, worker_ref)
    if request != nil do
      GenServer.reply(request.from, {:error, :timeout})
    end
    {:noreply, ~M{state|pending}}
  end

  ##############################
  # Internal Calls
  ##############################

  def do_summon(~M{pid, process_key, callback, initial_state}) do
    Ghoul.Worker.create(pid, process_key, callback, initial_state)
  end

end
