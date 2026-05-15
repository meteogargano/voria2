defmodule Voria2.Network.FaultAutoClearTest do
  use Voria2.DataCase, async: false
  import Voria2.MeasurementsHelpers
  alias Voria2.Network
  alias Voria2.Network.FaultClearer

  defp setup_station_with_sensor do
    user = create_user()
    installation = create_installation(user)
    station = create_station(installation)
    mt = create_measurement_type(slug: "temperature", storage_type: :scalar)
    sensor = create_sensor_installation(station, mt)
    {station, sensor}
  end

  defp setup_webcam do
    user = create_user()
    installation = create_installation(user)
    webcam = create_webcam(installation)
    {webcam}
  end

  describe "FaultClearer.clear_station_sync/1" do
    test "clears active auto-offline fault" do
      {station, _} = setup_station_with_sensor()
      fault = create_auto_fault_for_station(station)

      FaultClearer.clear_station_sync(station.id)

      {:ok, fault_reloaded} = Network.get_fault(fault.id, authorize?: false)
      assert not is_nil(fault_reloaded.resolved_at)
      assert is_nil(fault_reloaded.resolved_by_id)
    end

    test "does not clear manual fault" do
      {station, _} = setup_station_with_sensor()
      fault = create_manual_fault_for_station(station, "physical damage")

      FaultClearer.clear_station_sync(station.id)

      {:ok, fault_reloaded} = Network.get_fault(fault.id, authorize?: false)
      assert is_nil(fault_reloaded.resolved_at)
    end

    test "no error when no active fault exists" do
      {station, _} = setup_station_with_sensor()

      assert :ok = FaultClearer.clear_station_sync(station.id)
    end

    test "clears only auto fault, leaves manual fault active" do
      {station, _} = setup_station_with_sensor()
      auto_fault = create_auto_fault_for_station(station)
      manual_fault = create_manual_fault_for_station(station, "manual issue")

      FaultClearer.clear_station_sync(station.id)

      {:ok, auto_reloaded} = Network.get_fault(auto_fault.id, authorize?: false)
      {:ok, manual_reloaded} = Network.get_fault(manual_fault.id, authorize?: false)

      assert not is_nil(auto_reloaded.resolved_at)
      assert is_nil(manual_reloaded.resolved_at)
    end
  end

  describe "FaultClearer.clear_webcam_sync/1" do
    test "clears active auto-offline fault for webcam" do
      {webcam} = setup_webcam()
      fault = create_auto_fault_for_webcam(webcam)

      FaultClearer.clear_webcam_sync(webcam.id)

      {:ok, fault_reloaded} = Network.get_fault(fault.id, authorize?: false)
      assert not is_nil(fault_reloaded.resolved_at)
    end

    test "does not clear manual fault for webcam" do
      {webcam} = setup_webcam()
      fault = create_manual_fault_for_webcam(webcam, "lens issue")

      FaultClearer.clear_webcam_sync(webcam.id)

      {:ok, fault_reloaded} = Network.get_fault(fault.id, authorize?: false)
      assert is_nil(fault_reloaded.resolved_at)
    end

    test "no error when no active fault for webcam" do
      {webcam} = setup_webcam()
      assert :ok = FaultClearer.clear_webcam_sync(webcam.id)
    end
  end

  describe "heartbeat via Ingest.dispatch" do
    setup do
      user = create_user()
      installation = create_installation(user)
      station = create_station(installation)
      mt = create_measurement_type(slug: "temperature", storage_type: :scalar)
      _sensor = create_sensor_installation(station, mt)

      # Ensure cache is warm for the sensor
      Voria2.Cache.invalidate_sensor(station.id, "temperature")

      {:ok, api_key} =
        Voria2.Network.generate_station_api_key(station.id, actor: user)

      {:ok, station_with_key} = Voria2.Cache.station_for_key(api_key.key)
      %{station: station_with_key, api_key: api_key}
    end

    test "ingest dispatching updates station heartbeat", %{station: station} do
      # Clear any existing heartbeat
      :ets.delete(:voria2_cache, {:station_heartbeat, station.id})

      params = %{
        "sensor" => "temperature",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "value" => 22.5
      }

      Voria2.Ingest.dispatch(station, params)

      assert not is_nil(Voria2.Cache.station_last_seen(station.id))
    end

    test "ingest clears auto-offline fault asynchronously", %{station: station} do
      fault = create_auto_fault_for_station(station)

      params = %{
        "sensor" => "temperature",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "value" => 22.5
      }

      Voria2.Ingest.dispatch(station, params)

      # Allow async task to complete
      Process.sleep(200)

      {:ok, fault_reloaded} = Network.get_fault(fault.id, authorize?: false)
      assert not is_nil(fault_reloaded.resolved_at)
    end
  end
end
