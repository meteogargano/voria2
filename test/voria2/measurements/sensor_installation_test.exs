defmodule Voria2.Measurements.SensorInstallationTest do
  use Voria2.DataCase, async: false
  import Voria2.MeasurementsHelpers

  alias Voria2.Measurements

  setup do
    user = create_user()
    installation = create_installation(user)
    station = create_station(installation)
    mt = create_measurement_type()
    %{user: user, station: station, mt: mt}
  end

  describe "CRUD" do
    test "create", %{station: station, mt: mt} do
      sensor = create_sensor_installation(station, mt)
      assert sensor.station_id == station.id
      assert sensor.measurement_type_id == mt.id
    end

    test "read by id", %{station: station, mt: mt} do
      sensor = create_sensor_installation(station, mt)
      assert {:ok, found} = Measurements.get_sensor_installation(sensor.id, authorize?: false)
      assert found.id == sensor.id
    end

    test "update notes", %{station: station, mt: mt, user: user} do
      sensor = create_sensor_installation(station, mt)

      assert {:ok, updated} =
               Measurements.update_sensor_installation(sensor, %{notes: "test note"}, actor: user)

      assert updated.notes == "test note"
    end

    test "destroy", %{station: station, mt: mt, user: user} do
      sensor = create_sensor_installation(station, mt)
      assert :ok = Measurements.destroy_sensor_installation(sensor, actor: user)
    end
  end

  describe "decommission" do
    test "sets removed_at to today and is_active becomes false", %{
      station: station,
      mt: mt,
      user: user
    } do
      sensor = create_sensor_installation(station, mt)
      assert {:ok, decommissioned} = Measurements.decommission_sensor(sensor, actor: user)
      assert decommissioned.removed_at == Date.utc_today()
      loaded = Ash.load!(decommissioned, [:is_active], authorize?: false)
      assert loaded.is_active == false
    end
  end

  describe "rain_mode field" do
    test "persisted correctly", %{station: station, mt: mt} do
      sensor = create_sensor_installation(station, mt, rain_mode: :cumulative)
      assert sensor.rain_mode == :cumulative
    end
  end

  describe "policies" do
    test "only station owner can update", %{station: station, mt: mt} do
      other = create_user()
      sensor = create_sensor_installation(station, mt)

      assert {:error, %Ash.Error.Forbidden{}} =
               Measurements.update_sensor_installation(sensor, %{notes: "hack"}, actor: other)
    end

    test "only station owner can destroy", %{station: station, mt: mt} do
      other = create_user()
      sensor = create_sensor_installation(station, mt)

      assert {:error, %Ash.Error.Forbidden{}} =
               Measurements.destroy_sensor_installation(sensor, actor: other)
    end
  end
end
