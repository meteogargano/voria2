defmodule Voria2.Network.FaultTest do
  use Voria2.DataCase, async: false
  import Voria2.MeasurementsHelpers
  alias Voria2.Network

  defp setup_station do
    user = create_user()
    installation = create_installation(user)
    station = create_station(installation)
    {user, station}
  end

  defp setup_webcam do
    user = create_user()
    installation = create_installation(user)
    webcam = create_webcam(installation)
    {user, webcam}
  end

  defp setup_sensor do
    user = create_user()
    installation = create_installation(user)
    station = create_station(installation)
    mt = create_measurement_type(slug: "temperature", storage_type: :scalar)
    sensor = create_sensor_installation(station, mt)
    {user, station, sensor}
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Create auto-offline faults
  # ─────────────────────────────────────────────────────────────────────────

  describe "create auto-offline fault" do
    test "for station: attributes correct" do
      {_, station} = setup_station()
      now = DateTime.utc_now()

      fault = create_auto_fault_for_station(station, detected_at: now)

      assert fault.fault_type == :auto_offline
      assert fault.reason == "offline"
      assert fault.station_id == station.id
      assert is_nil(fault.webcam_id)
      assert is_nil(fault.sensor_installation_id)
      assert is_nil(fault.resolved_at)
      assert is_nil(fault.resolved_by_id)
    end

    test "for webcam: attributes correct" do
      {_, webcam} = setup_webcam()

      fault = create_auto_fault_for_webcam(webcam)

      assert fault.fault_type == :auto_offline
      assert fault.reason == "offline"
      assert fault.webcam_id == webcam.id
      assert is_nil(fault.station_id)
      assert is_nil(fault.sensor_installation_id)
    end

    test "for sensor_installation: attributes correct" do
      {_, _, sensor} = setup_sensor()

      fault = create_auto_fault_for_sensor(sensor)

      assert fault.fault_type == :auto_offline
      assert fault.reason == "offline"
      assert fault.sensor_installation_id == sensor.id
      assert is_nil(fault.station_id)
      assert is_nil(fault.webcam_id)
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Create manual faults
  # ─────────────────────────────────────────────────────────────────────────

  describe "create manual fault" do
    test "with custom reason" do
      {_, station} = setup_station()

      fault = create_manual_fault_for_station(station, "sensor physically damaged")

      assert fault.fault_type == :manual
      assert fault.reason == "sensor physically damaged"
      assert fault.station_id == station.id
      assert is_nil(fault.resolved_at)
    end

    test "for webcam with custom reason" do
      {_, webcam} = setup_webcam()

      fault = create_manual_fault_for_webcam(webcam, "lens fogged")

      assert fault.fault_type == :manual
      assert fault.reason == "lens fogged"
    end

    test "for sensor with custom reason" do
      {_, _, sensor} = setup_sensor()

      fault = create_manual_fault_for_sensor(sensor, "calibration drift detected")

      assert fault.fault_type == :manual
      assert fault.reason == "calibration drift detected"
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Resolve
  # ─────────────────────────────────────────────────────────────────────────

  describe "resolve fault" do
    test "sets resolved_at and resolved_by_id" do
      {_, station} = setup_station()
      admin = create_admin()
      fault = create_auto_fault_for_station(station)

      assert {:ok, resolved} =
               Network.resolve_fault(fault, %{resolved_by_id: admin.id}, authorize?: false)

      assert not is_nil(resolved.resolved_at)
      assert resolved.resolved_by_id == admin.id
    end

    test "resolved_by_id can be nil (auto-clear)" do
      {_, station} = setup_station()
      fault = create_auto_fault_for_station(station)

      assert {:ok, resolved} =
               Network.resolve_fault(fault, %{resolved_by_id: nil}, authorize?: false)

      assert not is_nil(resolved.resolved_at)
      assert is_nil(resolved.resolved_by_id)
    end

    test "cannot resolve an already-resolved fault" do
      {_, station} = setup_station()
      fault = create_auto_fault_for_station(station)
      {:ok, _resolved} = Network.resolve_fault(fault, %{resolved_by_id: nil}, authorize?: false)

      # Re-fetch to get resolved state
      {:ok, fault_reloaded} = Network.get_fault(fault.id, authorize?: false)

      assert {:error, _} =
               Network.resolve_fault(fault_reloaded, %{resolved_by_id: nil}, authorize?: false)
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Validation: exactly one subject
  # ─────────────────────────────────────────────────────────────────────────

  describe "validation: exactly one subject" do
    test "cannot set both station_id and webcam_id" do
      user = create_user()
      installation = create_installation(user)
      station = create_station(installation)
      webcam = create_webcam(installation)
      now = DateTime.utc_now()

      assert {:error, _} =
               Network.detect_offline_fault(
                 %{station_id: station.id, webcam_id: webcam.id, detected_at: now},
                 authorize?: false
               )
    end

    test "cannot set zero subjects" do
      now = DateTime.utc_now()

      assert {:error, _} =
               Network.detect_offline_fault(%{detected_at: now}, authorize?: false)
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Query actions
  # ─────────────────────────────────────────────────────────────────────────

  describe "active_faults_for_station" do
    test "returns only unresolved faults" do
      {_, station} = setup_station()

      fault1 = create_auto_fault_for_station(station)
      _fault2 = create_manual_fault_for_station(station, "test")

      # Resolve fault1
      Network.resolve_fault(fault1, %{resolved_by_id: nil}, authorize?: false)

      {:ok, active} = Network.active_faults_for_station(station.id, authorize?: false)

      assert length(active) == 1
      assert hd(active).fault_type == :manual
    end

    test "returns empty list when all resolved" do
      {_, station} = setup_station()
      fault = create_auto_fault_for_station(station)
      Network.resolve_fault(fault, %{resolved_by_id: nil}, authorize?: false)

      {:ok, active} = Network.active_faults_for_station(station.id, authorize?: false)
      assert active == []
    end
  end

  describe "fault_history_for_station" do
    test "returns all faults sorted by detected_at desc" do
      {_, station} = setup_station()
      t1 = DateTime.add(DateTime.utc_now(), -3600, :second)
      t2 = DateTime.add(DateTime.utc_now(), -1800, :second)
      t3 = DateTime.utc_now()

      f1 = create_auto_fault_for_station(station, detected_at: t1)
      f2 = create_manual_fault_for_station(station, "reason", detected_at: t2)
      f3 = create_auto_fault_for_station(station, detected_at: t3)

      Network.resolve_fault(f1, %{resolved_by_id: nil}, authorize?: false)

      {:ok, history} = Network.fault_history_for_station(station.id, authorize?: false)

      assert length(history) == 3
      ids = Enum.map(history, & &1.id)
      assert ids == [f3.id, f2.id, f1.id]
    end
  end

  describe "active_auto_fault_for_station" do
    test "returns only auto_offline faults" do
      {_, station} = setup_station()
      _manual = create_manual_fault_for_station(station, "manual issue")
      auto = create_auto_fault_for_station(station)

      {:ok, found} = Network.active_auto_fault_for_station(station.id, authorize?: false)

      assert length(found) == 1
      assert hd(found).id == auto.id
    end

    test "returns empty when auto fault is resolved" do
      {_, station} = setup_station()
      fault = create_auto_fault_for_station(station)
      Network.resolve_fault(fault, %{resolved_by_id: nil}, authorize?: false)

      {:ok, found} = Network.active_auto_fault_for_station(station.id, authorize?: false)
      assert found == []
    end
  end

  describe "auto and manual faults coexist" do
    test "both types active for same station" do
      {_, station} = setup_station()

      create_auto_fault_for_station(station)
      create_manual_fault_for_station(station, "manual inspection needed")

      {:ok, active} = Network.active_faults_for_station(station.id, authorize?: false)
      assert length(active) == 2

      types = Enum.map(active, & &1.fault_type) |> Enum.sort()
      assert types == [:auto_offline, :manual]
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Policies
  # ─────────────────────────────────────────────────────────────────────────

  describe "policies: read access" do
    test "public (no actor) can read faults" do
      {_, station} = setup_station()
      create_auto_fault_for_station(station)

      assert {:ok, faults} = Network.fault_history_for_station(station.id)
      assert length(faults) == 1
    end

    test "non-admin user can read fault history" do
      {_, station} = setup_station()
      user = create_user()
      create_auto_fault_for_station(station)

      assert {:ok, faults} = Network.fault_history_for_station(station.id, actor: user)
      assert length(faults) == 1
    end
  end

  describe "policies: write access" do
    test "admin can create manual fault" do
      {_, station} = setup_station()
      admin = create_admin()

      assert {:ok, fault} =
               Network.report_manual_fault(
                 %{
                   station_id: station.id,
                   reason: "manual from admin",
                   detected_at: DateTime.utc_now()
                 },
                 actor: admin
               )

      assert fault.fault_type == :manual
    end

    test "admin can resolve fault" do
      {_, station} = setup_station()
      admin = create_admin()
      fault = create_auto_fault_for_station(station)

      assert {:ok, resolved} =
               Network.resolve_fault(fault, %{resolved_by_id: admin.id}, actor: admin)

      assert not is_nil(resolved.resolved_at)
    end

    test "non-admin cannot create manual fault" do
      {_, station} = setup_station()
      user = create_user()

      assert {:error, %Ash.Error.Forbidden{}} =
               Network.report_manual_fault(
                 %{
                   station_id: station.id,
                   reason: "unauthorized attempt",
                   detected_at: DateTime.utc_now()
                 },
                 actor: user
               )
    end

    test "non-admin cannot resolve fault" do
      {_, station} = setup_station()
      user = create_user()
      fault = create_auto_fault_for_station(station)

      assert {:error, %Ash.Error.Forbidden{}} =
               Network.resolve_fault(fault, %{resolved_by_id: nil}, actor: user)
    end
  end
end
