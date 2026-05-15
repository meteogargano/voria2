defmodule Voria2.Network.FaultSchedulerTest do
  use Voria2.DataCase, async: false
  import Voria2.MeasurementsHelpers
  alias Voria2.Network
  alias Voria2.Network.FaultScheduler

  # Threshold in seconds for all tests (matches test.exs config of 5s)
  @threshold 5

  defp setup_station_with_sensor do
    user = create_user()
    installation = create_installation(user)
    station = create_station(installation)
    mt = create_measurement_type(slug: "temperature", storage_type: :scalar)
    sensor = create_sensor_installation(station, mt)
    {station, sensor}
  end

  defp setup_station_no_sensors do
    user = create_user()
    installation = create_installation(user)
    station = create_station(installation)
    {station}
  end

  defp setup_webcam do
    user = create_user()
    installation = create_installation(user)
    webcam = create_webcam(installation)
    {webcam}
  end

  # Clear ETS heartbeat before each test so DB fallback path is exercised
  defp clear_heartbeat(station_id) do
    :ets.delete(:voria2_cache, {:station_heartbeat, station_id})
  end

  defp clear_webcam_heartbeat(webcam_id) do
    :ets.delete(:voria2_cache, {:webcam_heartbeat, webcam_id})
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Station checks
  # ─────────────────────────────────────────────────────────────────────────

  describe "check_stations/1: auto-fault creation" do
    test "station with no measurements gets faulted" do
      {station, _sensor} = setup_station_with_sensor()
      clear_heartbeat(station.id)

      FaultScheduler.check_stations(@threshold)

      {:ok, active} = Network.active_auto_fault_for_station(station.id, authorize?: false)
      assert length(active) == 1
      assert hd(active).reason == "offline"
    end

    test "station with recent measurement (ETS heartbeat) is not faulted" do
      {station, _sensor} = setup_station_with_sensor()
      # Set a fresh heartbeat in ETS
      Voria2.Cache.touch_station(station.id)

      FaultScheduler.check_stations(@threshold)

      {:ok, active} = Network.active_auto_fault_for_station(station.id, authorize?: false)
      assert active == []
    end

    test "station already faulted is not double-faulted" do
      {station, _sensor} = setup_station_with_sensor()
      clear_heartbeat(station.id)

      FaultScheduler.check_stations(@threshold)
      FaultScheduler.check_stations(@threshold)

      {:ok, active} = Network.active_auto_fault_for_station(station.id, authorize?: false)
      assert length(active) == 1
    end

    test "inactive station is not checked" do
      user = create_user()
      installation = create_installation(user)

      station =
        Voria2.Network.create_station!(
          %{
            installation_id: installation.id,
            name: "Inactive Station",
            slug: "inactive-#{System.unique_integer([:positive])}",
            is_active: false
          },
          authorize?: false
        )

      clear_heartbeat(station.id)
      FaultScheduler.check_stations(@threshold)

      {:ok, active} = Network.active_auto_fault_for_station(station.id, authorize?: false)
      assert active == []
    end

    test "station with no active sensors is not faulted" do
      {station} = setup_station_no_sensors()
      clear_heartbeat(station.id)

      FaultScheduler.check_stations(@threshold)

      {:ok, active} = Network.active_auto_fault_for_station(station.id, authorize?: false)
      assert active == []
    end
  end

  describe "check_stations/1: DB fallback" do
    test "cold start: recent measurement in DB → not faulted" do
      {station, sensor} = setup_station_with_sensor()
      clear_heartbeat(station.id)

      # Record a fresh measurement (within threshold)
      record_temperature!(sensor, 20.0, DateTime.utc_now())

      FaultScheduler.check_stations(@threshold)

      {:ok, active} = Network.active_auto_fault_for_station(station.id, authorize?: false)
      assert active == []
    end

    test "cold start: stale measurement in DB → faulted" do
      {station, sensor} = setup_station_with_sensor()
      clear_heartbeat(station.id)

      # Record an old measurement (beyond threshold of 5 seconds)
      stale_time = DateTime.add(DateTime.utc_now(), -(@threshold + 60), :second)
      record_temperature!(sensor, 15.0, stale_time)

      FaultScheduler.check_stations(@threshold)

      {:ok, active} = Network.active_auto_fault_for_station(station.id, authorize?: false)
      assert length(active) == 1
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Webcam checks
  # ─────────────────────────────────────────────────────────────────────────

  describe "check_webcams/1: auto-fault creation" do
    test "webcam with no shots gets faulted" do
      {webcam} = setup_webcam()
      clear_webcam_heartbeat(webcam.id)
      # Ensure no cached shot
      :ets.delete(:voria2_cache, {:latest_shot, webcam.id})

      FaultScheduler.check_webcams(@threshold)

      {:ok, active} = Network.active_auto_fault_for_webcam(webcam.id, authorize?: false)
      assert length(active) == 1
      assert hd(active).reason == "offline"
    end

    test "webcam with recent shot (ETS heartbeat) is not faulted" do
      {webcam} = setup_webcam()
      Voria2.Cache.touch_webcam(webcam.id)

      FaultScheduler.check_webcams(@threshold)

      {:ok, active} = Network.active_auto_fault_for_webcam(webcam.id, authorize?: false)
      assert active == []
    end

    test "webcam already faulted is not double-faulted" do
      {webcam} = setup_webcam()
      clear_webcam_heartbeat(webcam.id)
      :ets.delete(:voria2_cache, {:latest_shot, webcam.id})

      FaultScheduler.check_webcams(@threshold)
      FaultScheduler.check_webcams(@threshold)

      {:ok, active} = Network.active_auto_fault_for_webcam(webcam.id, authorize?: false)
      assert length(active) == 1
    end

    test "inactive webcam is not checked" do
      user = create_user()
      installation = create_installation(user)
      n = System.unique_integer([:positive])

      webcam =
        Voria2.Network.create_webcam!(
          %{
            installation_id: installation.id,
            name: "Inactive Webcam",
            slug: "inactive-webcam-#{n}",
            is_active: false
          },
          authorize?: false
        )

      clear_webcam_heartbeat(webcam.id)
      FaultScheduler.check_webcams(@threshold)

      {:ok, active} = Network.active_auto_fault_for_webcam(webcam.id, authorize?: false)
      assert active == []
    end
  end

  describe "check_webcams/1: DB fallback" do
    test "cold start: no shots in DB → faulted" do
      {webcam} = setup_webcam()
      clear_webcam_heartbeat(webcam.id)
      :ets.delete(:voria2_cache, {:latest_shot, webcam.id})

      FaultScheduler.check_webcams(@threshold)

      {:ok, active} = Network.active_auto_fault_for_webcam(webcam.id, authorize?: false)
      assert length(active) == 1
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Auto-clear after fault
  # ─────────────────────────────────────────────────────────────────────────

  describe "station fault then recovery" do
    test "fault created when stale, cleared when heartbeat resumes" do
      {station, _sensor} = setup_station_with_sensor()
      clear_heartbeat(station.id)

      # 1. Station is stale → fault created
      FaultScheduler.check_stations(@threshold)
      {:ok, active} = Network.active_auto_fault_for_station(station.id, authorize?: false)
      assert length(active) == 1

      # 2. Hardware comes back (heartbeat updated)
      Voria2.Cache.touch_station(station.id)
      Voria2.Network.FaultClearer.clear_station_sync(station.id)

      # 3. Active faults cleared
      {:ok, active_after} = Network.active_auto_fault_for_station(station.id, authorize?: false)
      assert active_after == []

      # 4. History still shows the resolved fault
      {:ok, history} = Network.fault_history_for_station(station.id, authorize?: false)
      assert length(history) == 1
      assert not is_nil(hd(history).resolved_at)
    end
  end
end
