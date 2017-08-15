defmodule GhoulSpec do
  use ESpec
  @table :ghoul_spec
  before_all do
    :ets.new(@table, [:public, :named_table, :set])
  end

  describe "summon" do
    it "executes code after a process has died" do
      :ets.insert(@table, {:summon_1, false})
      expect :ets.lookup(@table, :summon_1) |> to(eq(summon_1: false))
      spawn(fn ->
        Ghoul.summon(:summon_1, on_death: fn _, _, _ -> :ets.insert(@table, {:summon_1, true}) end)
      end)
      # now, give the process time to live, die, and have ghoul execute
      Process.sleep(50)
      expect :ets.lookup(@table, :summon_1) |> to(eq(summon_1: true))
    end

    it "passes in the proper args" do
      :ets.insert(@table, {:summon_2, []})
      expect :ets.lookup(@table, :summon_2) |> to(eq(summon_2: []))
      spawn(fn ->
        Ghoul.summon(:summon_2, on_death: fn a, b, c -> :ets.insert(@table, {:summon_2, [a, b, c]}) end, initial_state: :init)
      end)
      # now, give the process time to live, die, and have ghoul execute
      Process.sleep(50)
      expect :ets.lookup(@table, :summon_2) |> to(eq(summon_2: [:summon_2, :normal, :init]))
    end
  end

  describe "banish" do
    it "prevents the execution of the callback" do
      :ets.insert(@table, {:banish_1, false})
      expect :ets.lookup(@table, :banish_1) |> to(eq(banish_1: false))
      spawn(fn ->
        Ghoul.summon(:banish_1, on_death: fn _,_,_ -> :ets.insert(@table, {:banish_1, true}) end)
        Ghoul.banish(:banish_1)
      end)
      # now, give the process time to live, die, and have ghoul *not* execute
      Process.sleep(50)
      expect :ets.lookup(@table, :banish_1) |> to(eq(banish_1: false))
    end
    it "returns :ok if it succeeds" do
      Ghoul.summon(:banish_2)
      expect Ghoul.banish(:banish_2) |> to(eq(:ok))
    end
    it "returns error tuple if process_key is invalid" do
      expect Ghoul.banish(:banish_3) |> to(eq({:error, :no_process}))
    end
  end

  describe "get_state" do
    it "returns {:ok, state} if it works" do
      Ghoul.summon(:get_state_1, initial_state: :init)
      expect Ghoul.get_state(:get_state_1) |> to(eq({:ok, :init}))
      Ghoul.set_state(:get_state_1, :next)
      expect Ghoul.get_state(:get_state_1) |> to(eq({:ok, :next}))
    end
    it "returns error tuple if process_key is invalid" do
      Ghoul.get_state(:get_state_2) |> to(eq({:error, :no_process}))
    end
  end

  describe "set state" do
    it "updates the ghoul_state for the callback" do
      :ets.insert(@table, {:set_state_1, nil})
      expect :ets.lookup(@table, :set_state_1) |> to(eq(set_state_1: nil))
      spawn(fn ->
        Ghoul.summon(:set_state_1, on_death: fn _, _, c -> :ets.insert(@table, {:set_state_1, c}) end)
        Ghoul.set_state(:set_state_1, :updated_state)
      end)
      # now, give the process time to live, die, and have ghoul execute
      Process.sleep(50)
      expect :ets.lookup(@table, :set_state_1) |> to(eq(set_state_1: :updated_state))
    end

    it "returns {:ok, old_state} tuple if it works" do
      Ghoul.summon(:set_state_2, initial_state: :old_state)
      expect Ghoul.set_state(:set_state_2, :new_state) |> to(eq({:ok, :old_state}))
    end

    it "returns error tuple if process_key is invalid" do
      expect Ghoul.set_state(:set_state_3, :new_state) |> to(eq({:error, :no_process}))
    end
  end

  describe "reap_in" do
    it "kills the pid after n millisconds" do
      pid = spawn(fn ->
        Ghoul.summon(:reap_in_1)
        Ghoul.reap_in(:reap_in_1, :timeout, 20)
        Process.sleep(1000)
      end)
      expect Process.alive?(pid) |> to(eq(true))
      Process.sleep(50) # give the pid time to live and ghoul to reap it
      expect Process.alive?(pid) |> to(eq(false))
    end

    it "kills the pid with the proper reason" do
      :ets.insert(@table, {:reap_in_2, nil})
      expect :ets.lookup(@table, :reap_in_2) |> to(eq(reap_in_2: nil))
      spawn(fn ->
        Ghoul.summon(:reap_in_2, on_death: fn _, b, _ -> :ets.insert(@table, {:reap_in_2, b}) end)
        Ghoul.reap_in(:reap_in_2, :timeout, 20)
        Process.sleep(1000)
      end)
      # now, give the process time to live, die, and have ghoul execute
      Process.sleep(50)
      expect :ets.lookup(@table, :reap_in_2) |> to(eq(reap_in_2: :timeout))
    end

    # testing these will be very timing sensitive.  Maybe worth adding a message
    # to the pid?

    it "can be deferred by multiple calls" do
      pid = spawn(fn ->
        Ghoul.summon(:reap_in_3)
        for _ <- 1..10 do
          Ghoul.reap_in(:reap_in_3, :timeout, 20)
          Process.sleep(10)
        end
      end)
      # now, give the process time to live, defer reaping, and have ghoul not execute
      Process.sleep(50)
      expect Process.alive?(pid) |> to(eq(true))
    end

    it "can be canceled" do
      pid = spawn(fn ->
        Ghoul.summon(:reap_in_4)
        Ghoul.reap_in(:reap_in_4, :timeout, 20)
        Ghoul.cancel_reap(:reap_in_4)
        Process.sleep(100)
      end)
      # now, give the process time to live, cancel reaping, and have ghoul not execute
      Process.sleep(50)
      expect Process.alive?(pid) |> to(eq(true))
    end
    it "returns ok if it works" do
      Ghoul.summon(:reap_in_5)
      expect Ghoul.reap_in(:reap_in_5, :timeout, 2000) |> to(eq(:ok))
      Ghoul.cancel_reap(:reap_in_5)
    end
    it "returns error tuple if process_key is invalid" do
      expect Ghoul.reap_in(:reap_in_6, :timeout, 200) |> to(eq({:error, :no_process}))
    end
  end

  describe "ttl" do
    it "returns an integer if the timer hasn't elapsed" do
      spawn(fn ->
        Ghoul.summon(:ttl_1, on_death: fn _, b, _ -> :ets.insert(@table, {:ttl_1, b}) end)
        Ghoul.reap_in(:ttl_1, :timeout, 200)
        Process.sleep(1000)
      end)
      Process.sleep(100)
      {:ok, ttl} = Ghoul.ttl(:ttl_1)
      expect ttl |> to(be_between 0, 100)
    end

    it "returns false if the timer isn't set" do
      spawn(fn ->
        Ghoul.summon(:ttl_2, on_death: fn _, b, _ -> :ets.insert(@table, {:ttl_2, b}) end)
        Process.sleep(1000)
      end)
      Process.sleep(100)
      expect Ghoul.ttl(:ttl_2) |> to(eq({:ok, false}))
    end

    it "returns error tuple if process_key is invalid" do
      expect Ghoul.ttl(:ttl_3) |> to(eq({:error, :no_process}))
    end
  end


end
