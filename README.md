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
defmodule LedExample do
  use GenServer

  # ...snip...

  def init([]) do
    Ghoul.summon(LedExample, on_death: &cleanup/3)
    turn_on_led()
    {:ok, %State{}}
  end

  def cleanup(LedExample, _reason, _ghoul_state) do
    turn_off_led()
  end

  # ...snip...
end
```

It is important to note that `Ghoul.summon/2` will block during subsequent calls
for a given process_key (in this example, `LedServer`) until the cleanup code
has completed. Thus, the call to `Ghoul.summon/2` should happen **before** any
side-effect code (e.g. `turn_on_led/0`), and any side-effect code in the cleanup
method should be synchronous to avoid race-conditions when, e.g., a Supervisor
restarts the GenServer in question.

### Timeout Example

In this highly notional example, a GenServer managing an external server
transitions between multiple states with varying timeout rules and cleanup
logic.

The server should boot within 100ms, initialize within 50ms, and then respond
to a test request within 20ms

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

Parameters:

Return value:


#### `get_state/1`

Parameters:

Return value:


#### `set_state/2`

Parameters:

Return value:


#### `reap_in/3`

Parameters:

Return value:


#### `cancel_reap/1`

Parameters:

Return value:


#### `ttl/1`

Parameters:

Return value:



## Installation

Add `{:ghoul, "~> 0.1"},` to your mix deps.
