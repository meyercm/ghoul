defmodule Ghoul do
  # def on_death(process_key, reason, ghoul_state)

  def summon(pid \\ :self, process_key, on_death, initial_state)
  def summon(:self, process_key, on_death, initial_state) do
    summon(self(), process_key, on_death, initial_state)
  end
  def summon(pid, process_key, on_death, initial_state) do
    Ghoul.Watcher.summon(pid, process_key, on_death, initial_state)
  end

  def banish(process_key) do
    Ghoul.Watcher.banish(process_key)
  end

  def get_state(process_key) do
    Ghoul.Worker.get_state(process_key)
  end

  def set_state(process_key, new_state) do
    Ghoul.Worker.set_state(process_key, new_state)
  end

  def reap_in(process_key, reason, delay_ms) do
    Ghoul.Worker.reap_in(process_key, reason, delay_ms)
  end
end
