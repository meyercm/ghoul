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
        Ghoul.summon(:summon_1, fn _, _, _ -> :ets.insert(@table, {:summon_1, true}) end, nil)
      end)
      # now, give the process time to live, die, and have ghoul execute
      Process.sleep(50)
      expect :ets.lookup(@table, :summon_1) |> to(eq(summon_1: true))
    end

    it "passes in the proper args" do
      :ets.insert(@table, {:summon_2, []})
      expect :ets.lookup(@table, :summon_2) |> to(eq(summon_2: []))
      spawn(fn ->
        Ghoul.summon(:summon_2, fn a, b, c -> :ets.insert(@table, {:summon_2, [a, b, c]}) end, :initial_state)
      end)
      # now, give the process time to live, die, and have ghoul execute
      Process.sleep(50)
      expect :ets.lookup(@table, :summon_2) |> to(eq(summon_2: [:summon_2, :normal, :initial_state]))
    end
  end

  describe "banish" do
    it "prevents the execution of the callback" do
      :ets.insert(@table, {:banish_1, false})
      expect :ets.lookup(@table, :banish_1) |> to(eq(banish_1: false))
      spawn(fn ->
        Ghoul.summon(:banish_1, fn _,_,_ -> :ets.insert(@table, {:banish_1, true}) end, nil)
        Ghoul.banish(:banish_1)
      end)
      # now, give the process time to live, die, and have ghoul *not* execute
      Process.sleep(50)
      expect :ets.lookup(@table, :banish_1) |> to(eq(banish_1: false))
    end
  end

  describe "set state" do
    it "updates the ghoul_state for the callback" do
      :ets.insert(@table, {:set_state_1, nil})
      expect :ets.lookup(@table, :set_state_1) |> to(eq(set_state_1: nil))
      spawn(fn ->
        Ghoul.summon(:set_state_1, fn _, _, c -> :ets.insert(@table, {:set_state_1, c}) end, :initial_state)
        Ghoul.set_state(:set_state_1, :updated_state)
      end)
      # now, give the process time to live, die, and have ghoul execute
      Process.sleep(50)
      expect :ets.lookup(@table, :set_state_1) |> to(eq(set_state_1: :updated_state))
    end
  end

  describe "reap_in" do
    it "kills the pid after n millisconds" do
      pid = spawn(fn ->
        Ghoul.summon(:reap_in_1, nil, :initial_state)
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
        Ghoul.summon(:reap_in_2, fn _, b, _ -> :ets.insert(@table, {:reap_in_2, b}) end, :initial_state)
        Ghoul.reap_in(:reap_in_2, :timeout, 20)
        Process.sleep(1000)
      end)
      # now, give the process time to live, die, and have ghoul execute
      Process.sleep(50)
      expect :ets.lookup(@table, :reap_in_2) |> to(eq(reap_in_2: :timeout))
    end

    # testing these will be very timing sensitive.  Maybe worth adding a message
    # to the pid?
    it "can be deferred by multiple calls"
    it "can be canceled"
  end


end
