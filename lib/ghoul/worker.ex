defmodule Ghoul.Worker do
  use GenServer
  import ShorterMaps
  use PatternTap

  ##############################
  # API
  ##############################
  def get_worker_for(process_key) do
    case :gproc.lookup_pids({:n, :l, process_key}) do
      [] -> {:error, :no_process}
      [pid] -> {:ok, pid}
    end
  end

  def create(pid, process_key, callback, initial_state) do
    Ghoul.Worker.Supervisor.start_child(pid, process_key, callback, initial_state)
  end

  def get_state(process_key) do
    get_worker_for(process_key)
    |> tap({:ok, pid} ~> pid)
    |> GenServer.call(:get_state)
  end

  def set_state(process_key, new_state) do
    get_worker_for(process_key)
    |> tap({:ok, pid} ~> pid)
    |> GenServer.call({:set_state, new_state})
  end

  def reap_in(process_key, reason, delay_ms) when is_integer(delay_ms) and delay_ms >= 0 do
    get_worker_for(process_key)
    |> tap({:ok, pid} ~> pid)
    |> GenServer.call({:reap_in, reason, delay_ms})
  end

  def cancel_reap(process_key) do
    get_worker_for(process_key)
    |> tap({:ok, pid} ~> pid)
    |> GenServer.call(:cancel_reap)
  end

  def stop(pid) do
    GenServer.call(pid, :stop)
  end

  def start_link(pid, process_key, callback, initial_state) do
    GenServer.start_link(__MODULE__, [pid, process_key, callback, initial_state])
  end

  defmodule State do
    @doc false
    defstruct [
      process_key: nil,
      pid: nil,
      callback: nil,
      ghoul_state: nil,
      reap_timer: nil,
    ]
  end

  ##############################
  # GenServer Callbacks
  ##############################

  def init([pid, process_key, callback, ghoul_state]) do
    :gproc.reg({:n, :l, process_key})
    Process.monitor(pid)
    {:ok, ~M{%State process_key, pid, callback, ghoul_state}}
  end

  def handle_call(:get_state, _from, ~M{ghoul_state} = state) do
    {:reply, ghoul_state, state}
  end

  def handle_call({:set_state, new_state}, _from, state) do
    {:reply, :ok, %{state|ghoul_state: new_state}}
  end

  def handle_call({:reap_in, reason, delay_ms}, _from, ~M{reap_timer} = state) do
    cancel_reap_timer(reap_timer)
    reap_timer = Process.send_after(self(), {:reap, reason}, delay_ms)
    {:reply, :ok, ~M{state|reap_timer}}
  end

  def handle_call(:cancel_reap, _from, ~M{reap_timer} = state) do
    cancel_reap_timer(reap_timer)
    {:reply, :ok, %{state|reap_timer: nil}}
  end

  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end

  def handle_info({:reap, reason}, ~M{pid} = state) do
    Process.exit(pid, reason)
    {:noreply, state}
  end

  def handle_info({:DOWN, _monitor_ref, :process, pid, reason}, ~M{pid, callback, process_key, ghoul_state} = state) do
    if is_function(callback) do
      callback.(process_key, reason, ghoul_state)
    end
    {:stop, :normal, state}
  end

  ##############################
  # Internal Calls
  ##############################

  def cancel_reap_timer(nil), do: nil
  def cancel_reap_timer(ref), do: Process.cancel_timer(ref)
end
