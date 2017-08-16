defmodule Ghoul do
  @moduledoc """
  Ghoul is a utility for managing process death-cycles, calling cleanup code
  post-mortem, or actively reaping processes that need killing.

  Generally, a GenServer should call `summon/2` in it's init function, and
  provide an arity 3 function to conduct resource cleanup.  `banish/1` can be
  used if you change your mind about cleanup.

  `get_state/1` and `set_state/2` are useful to provide process state to the
  cleanup code.

  `reap_in/3`, `cancel_reap/1`, and `ttl/1` are useful for killing processes
  after a certain amount of time has passed, changing your mind, and seeing how
  long you have to decide, respectively.
  """

  import ShorterMaps

  @type on_death_callback :: (term, atom, term -> any)
  @type process_key :: any

  @default_summon_opts %{
    pid: :self,
    on_death: nil,
    initial_state: nil,
    timeout_ms: 5_000,
  }
  @doc """
  Summon a Ghoul to watch a process.  When the pid terminates, the Ghoul will
  execute the function in the `on_death` option, passing in the `process_key`,
  the `reason` the pid exited, and the current `ghoul_state`.

  ### Parameters
  * `process_key` - How this pid should be known to Ghoul. Will be passed to the
    `on_death` function as the first parameter.
  * `opts` - a keyword list or map with the following options:
    - `:pid` - which pid to have the Ghoul stalk.  Defaults to the calling pid.
    - `:on_death` - a function to be executed after the process dies. Defaults to
      `nil`, and nothing will be executed. Expects 3-arity function, to be
      called as `fun.(process_key, exit_reason, ghoul_state)` by the Ghoul.
    - `:initial_state` - the initial `ghoul_state` for this worker. Defaults to
      `nil`. The `ghoul_state` will be passed to the `on_death` function as the
      third parameter, and can be queried using `Ghoul.get_state/1` and changed
      using `Ghoul.set_state/2`
    - `:timeout_ms` - milliseconds to wait for Ghoul to finish cleaning up a
      previous incarnation of the process using this `process_key`. Defaults to
      5_000.
  """
  def summon(process_key, opts \\ @default_summon_opts)
  def summon(process_key, opts) when is_list(opts) do
    summon(process_key, Enum.into(opts, %{}))
  end
  def summon(process_key, opts) when is_map(opts) do
    ~M{pid, on_death, initial_state, timeout_ms} = Map.merge(@default_summon_opts, opts)
    pid = case pid do
      :self -> self()
      pid -> pid
    end
    Ghoul.Watcher.summon(pid, process_key, on_death, initial_state, timeout_ms)
  end

  @doc """
  Prevents a Ghoul from executing `reap_in` or `on_death` actions.

  ### Parameters
  * `process_key` - the `process_key` of the Ghoul to terminate
  """
  def banish(process_key) do
    Ghoul.Watcher.banish(process_key)
  end

  @doc """
  Gets the current state of a Ghoul worker.

  ### Parameters
  * `process_key` - the `process_key` of the Ghoul to terminate
  """
  def get_state(process_key) do
    Ghoul.Worker.get_state(process_key)
  end

  @doc """
  Sets the current state of a Ghoul worker.

  ### Parameters
  * `process_key` - the `process_key` of the Ghoul to terminate
  * `new_state` - the new value to use as the `ghoul_state`
  """
  def set_state(process_key, new_state) do
    Ghoul.Worker.set_state(process_key, new_state)
  end

  @doc """
  Instruct the ghoul to kill the process after a delay. Each time this method is
  called for a process, previous `reap_in` directives are canceled. This lets
  the Ghoul act as a deadman switch for a process, killing it should it fail to
  progress in an expected manner.

  ### Parameters
  * `process_key` - the `process_key` of the Ghoul to terminate
  * `reason` - the reason to pass to `Process.exit/2`
  * `delay_ms` - how long to wait until reaping the process. Any
  """
  def reap_in(process_key, reason, delay_ms) do
    Ghoul.Worker.reap_in(process_key, reason, delay_ms)
  end

  @doc """
  Cancel a pending reap.

  ### Parameters
  * `process_key` - the `process_key` of the Ghoul to prevent termination
  """
  def cancel_reap(process_key) do
    Ghoul.Worker.cancel_reap(process_key)
  end

  @doc """
  Time until a process is reaped.

  ### Parameters
  * `process_key` - the `process_key` of the Ghoul to query
  """
  def ttl(process_key) do
    Ghoul.Worker.ttl(process_key)
  end
end
