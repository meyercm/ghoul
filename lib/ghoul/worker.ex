defmodule Ghoul.Worker do
  @moduledoc false
  use GenServer
  import ShorterMaps
  use PatternTap

  ##############################
  # API
  ##############################

  @spec get_worker_for(Ghoul.process_key) :: {:ok, pid} | {:error, atom}
  def get_worker_for(process_key) do
    case :gproc.lookup_pids({:n, :l, {__MODULE__, process_key}}) do
      [] -> {:error, :no_process}
      [pid] -> {:ok, pid}
    end
  end

  @spec create(pid, Ghoul.process_key, Ghoul.on_death_callback, any) :: {:ok, pid} | {:error, atom}
  def create(pid, process_key, callback, initial_state) do
    Ghoul.Worker.Supervisor.start_child(pid, process_key, callback, initial_state)
  end

  @spec get_state(Ghoul.process_key) :: {:ok, any} | {:error, atom}
  def get_state(process_key) do
    call_by_process_key(process_key, :get_state)
  end

  @spec set_state(Ghoul.process_key, any) :: {:ok, any} | {:error, atom}
  def set_state(process_key, new_state) do
    call_by_process_key(process_key, {:set_state, new_state})
  end

  @spec reap_in(Ghoul.process_key, atom, non_neg_integer) :: :ok | {:error, atom}
  def reap_in(process_key, reason, delay_ms) when is_integer(delay_ms) and delay_ms >= 0 do
    call_by_process_key(process_key, {:reap_in, reason, delay_ms})
  end

  @spec cancel_reap(Ghoul.process_key) :: :ok | {:error, atom}
  def cancel_reap(process_key) do
    call_by_process_key(process_key, :cancel_reap)
  end

  @spec ttl(Ghoul.process_key) :: {:ok, non_neg_integer} | {:error, atom}
  def ttl(process_key) do
    call_by_process_key(process_key, :ttl)
  end

  def stop(pid) do
    GenServer.call(pid, :stop)
  end

  def start_link(pid, process_key, callback, initial_state) do
    GenServer.start_link(__MODULE__, [pid, process_key, callback, initial_state])
  end

  def call_by_process_key(process_key, call_arg) do
    case get_worker_for(process_key) do
      {:ok, pid} -> GenServer.call(pid, call_arg)
      error -> error
    end
  end

  defmodule State do
    @moduledoc false
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
    :gproc.reg({:n, :l, {__MODULE__, process_key}})
    Process.monitor(pid)
    {:ok, ~M{%State process_key, pid, callback, ghoul_state}}
  end

  def handle_call(:get_state, _from, ~M{ghoul_state} = state) do
    {:reply, {:ok, ghoul_state}, state}
  end

  def handle_call({:set_state, new_state}, _from, ~M{ghoul_state} = state) do
    {:reply, {:ok, ghoul_state}, %{state|ghoul_state: new_state}}
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

  def handle_call(:ttl, _from, %{reap_timer: nil} = state) do
    {:reply, {:ok, false}, state}
  end
  def handle_call(:ttl, _from, ~M{reap_timer} = state) do
    result = Process.read_timer(reap_timer)
    {:reply, {:ok, result}, state}
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
