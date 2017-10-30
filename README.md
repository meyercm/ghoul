## Ghoul

An undead cleanup crew for your processes.

[![Build Status](https://travis-ci.org/meyercm/ghoul.svg?branch=master)](https://travis-ci.org/meyercm/ghoul)
[![Hex.pm](https://img.shields.io/hexpm/v/ghoul.svg)](https://hex.pm/packages/ghoul)
[![Build Docs](https://img.shields.io/badge/documentation-v0.1.0-blue.svg)](https://hexdocs.pm/ghoul)

`{:ghoul, "~> 0.1"},`

### Motivation

Ghoul solves two problems for the OTP developer:

1) Robust execution of cleanup code after a process exits
2) Robust termination of a process that has exceeded timing expectations

Both of these problems can be handled in one-off manners, and the `:timeout` set
of responses for `GenServer` provides a builtin solution for simple use cases.
Ghoul steps in once the builtin functionality is no longer sufficient.

### Cleanup Example

Hardware interaction is a common motivation for wanting cleanup code. This is a
simple, notional example of tying an LED to the lifecycle of a particular
GenServer:

```elixir
defmodule Led.Worker do
  use GenServer

  # ...snip...

  def init([]) do
    Ghoul.summon(LedExample, on_death: &cleanup/3)
    turn_on_led()
    {:ok, %State{}}
  end

  # This method will be invoked by a separate process after the GenServer dies.
  def cleanup(LedExample, _reason, _ghoul_state) do
    turn_off_led()
  end

  # ...snip...
end
```

#### Important

`Ghoul.summon/2` will block during subsequent calls for a given process_key (in
this example, `LedServer`) until the cleanup code has completed. Thus, the call
to `Ghoul.summon/2` should happen **before** any side-effect code (e.g.
`turn_on_led/0`), and any side-effect code in the cleanup method should be
synchronous to avoid race-conditions when, e.g., a Supervisor restarts the
`GenServer` in question.

See the [sequence diagram][led_sequence] for this example for a detailed flow
and race condition analysis of the above example.

A useful side effect of this property is being able to rate-limit how quickly a
`GenServer` can be restarted.  Simply add `Process.sleep(time_ms)` as the last
line of the `on_death/3` callback, and restarts of the process will be spaced
out by `time_ms`.

### Timeout Example

In this notional example, a GenServer managing an external server transitions
between multiple states with varying timeout rules and cleanup logic.

The server should boot within 100ms, initialize within 50ms, and then respond
to a test request within 20ms.

Internally, our GenServer will transition from `:booting` -> `:initing` ->
`:testing` -> `:ready`

Details of the `~M` sigil can be found at the [ShorterMaps][shorter_maps] repo.

```elixir
defmodule FsmExample do
  use GenServer
  import ShorterMaps

  defmodule State do
    defstruct [port: nil, fsm: :not_init]
  end

  def init([]) do
    Ghoul.summon(FsmExample, on_death: &cleanup/3)
    # start the external server
    {:ok, port} = start_external_server()
    # provide the port to Ghoul for use during cleanup:
    Ghoul.set_state(FsmExample, port)
    # schedule this process for destruction if the external server fails to boot
    # within the specified timeout of 100ms.
    Ghoul.reap_in(FsmExample, :boot_timeout, 100)
    {:ok, ~M{%State port, fsm: :booting}}
  end


  def handle_info({port, "BOOTED"}, ~M{port, fsm: :booting}) do
    :ok = initialize_server(port)
    # this cancels the boot reaping, and replaces it with an init reaping:
    Ghoul.reap_in(FsmExample, :init_timeout, 50)
    {:noreply, %{state|fsm: :initing}}
  end
  def handle_info({port, "INIT COMPLETE"}, ~M{port, fsm: :initing}) do
    send_test_query(port)
    Ghoul.reap_in(FsmExample, :example_timeout, 20)
    {:noreply, %{state|fsm: :testing}}
  end
  def handle_info({port, "TEST COMPLETE"}, ~M{port, fsm: :testing}) do
    # prevent killing this process
    Ghoul.cancel_reap(FsmExample)
    {:noreply, %{state|fsm: :ready}}
  end

  def cleanup(FsmExample, :boot_timeout, port) do
    # server didn't boot, just close the port:
    close_server_port(port)
  end
  def cleanup(FsmExample, _reason, port) do
    disconnect_server(port)
    close_server_port(port)
  end
  # ...snip...
end
```

## API

#### `summon/2`

Summon a Ghoul to watch a process.  When the pid terminates, the Ghoul will
execute the function in the `on_death` option, passing in the `process_key`,
the `reason` the pid exited, and the current `ghoul_state`.

Parameters:

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

Return value:
`:ok | {:error, reason}`

#### `banish/1`

Stop the Ghoul for a process, preventing the `on_death/3` callback from
executing and preventing any upcoming reaping.

Parameters:

* `process_key` - the `process_key` of the Ghoul

Return value:
`:ok | {:error, reason}`

#### `get_state/1`

Gets the current state of a Ghoul worker, i.e. the 2nd argument for the
`on_death/3` callback.

Parameters:

* `process_key` - the `process_key` of the Ghoul

Return value:

{:ok, state}|{:error, reason}

#### `set_state/2`

Sets the current state of a Ghoul worker, to be passed as the second argument
to the `on_death/3` callback.

Parameters:

* `process_key` - the `process_key` of the Ghoul

Return value:

{:ok, state}|{:error, reason}

#### `reap_in/3`

Instruct the ghoul to kill the process after a delay. Each time this method is
called for a process, previous `reap_in` directives are canceled. This lets
the Ghoul act as a deadman switch for a process, killing it should it fail to
progress in an expected manner.

Parameters:

* `process_key` - the `process_key` of the Ghoul
* `reason` - the reason to pass to `Process.exit/2`
* `delay_ms` - how long to wait until reaping the process.

Return value:

`:ok | {:error, reason}`

#### `cancel_reap/1`

Cancel a pending reap.

Parameters:

* `process_key` - the `process_key` of the Ghoul

Return value:
`:ok | {:error, reason}`

#### `ttl/1`

Query a Ghoul to see how much time remains unil a reaping.  Result is in
milliseconds, or `false` if the process has already reaped.

Parameters:

* `process_key` - the `process_key` of the Ghoul

Return value:

`integer|false | {:error, reason}`


## Installation

Add `{:ghoul, "~> 0.1"},` to your mix deps.


[led_sequence]:
design/led_sequence.svg

[shorter_maps]:
https://github.com/meyercm/shorter_maps
