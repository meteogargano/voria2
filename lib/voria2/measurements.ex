defmodule Voria2.Measurements do
  use Ash.Domain, otp_app: :voria2

  resources do
    resource Voria2.Measurements.MeasurementType do
      define :create_measurement_type, action: :create
      define :list_measurement_types, action: :read
      define :get_measurement_type, action: :read, get_by: [:id]
      define :get_measurement_type_by_slug, action: :read, get_by: [:slug]
      define :update_measurement_type, action: :update
      define :destroy_measurement_type, action: :destroy
    end

    resource Voria2.Measurements.SensorInstallation do
      define :create_sensor_installation, action: :create
      define :list_sensor_installations, action: :read
      define :get_sensor_installation, action: :read, get_by: [:id]
      define :update_sensor_installation, action: :update
      define :decommission_sensor, action: :decommission
      define :destroy_sensor_installation, action: :destroy
    end

    resource Voria2.Measurements.TemperatureMeasurement do
      define :record_temperature, action: :record
      define :list_temperature_measurements, action: :read
      define :update_temperature, action: :update

      define :temperature_for_sensor,
        action: :for_sensor,
        args: [:sensor_installation_id, :from, :to]
    end

    resource Voria2.Measurements.HumidityMeasurement do
      define :record_humidity, action: :record
      define :list_humidity_measurements, action: :read
      define :update_humidity, action: :update

      define :humidity_for_sensor,
        action: :for_sensor,
        args: [:sensor_installation_id, :from, :to]
    end

    resource Voria2.Measurements.PressureMeasurement do
      define :record_pressure, action: :record
      define :list_pressure_measurements, action: :read
      define :update_pressure, action: :update

      define :pressure_for_sensor,
        action: :for_sensor,
        args: [:sensor_installation_id, :from, :to]
    end

    resource Voria2.Measurements.WindMeasurement do
      define :record_wind, action: :record
      define :list_wind_measurements, action: :read
      define :update_wind, action: :update
      define :wind_for_sensor, action: :for_sensor, args: [:sensor_installation_id, :from, :to]
    end

    resource Voria2.Measurements.RainMeasurement do
      define :record_rain_interval, action: :record_interval
      define :record_rain_cumulative, action: :record_cumulative
      define :list_rain_measurements, action: :read
      define :update_rain, action: :update
      define :rain_for_sensor, action: :for_sensor, args: [:sensor_installation_id, :from, :to]
    end

    resource Voria2.Measurements.CustomMeasurement do
      define :record_custom_measurement, action: :record
      define :list_custom_measurements, action: :read
      define :update_custom, action: :update
      define :custom_for_sensor, action: :for_sensor, args: [:sensor_installation_id, :from, :to]
    end

    resource Voria2.Measurements.RainCumulativeState do
      define :get_rain_cumulative_state, action: :for_sensor, args: [:sensor_installation_id]
      define :upsert_rain_cumulative_state, action: :upsert
    end

    resource Voria2.Measurements.Summaries.TemperatureSummary do
      define :temperature_summary, action: :calculate, args: [:station_id]
    end

    resource Voria2.Measurements.Summaries.HumidityPressureSummary do
      define :humidity_pressure_summary, action: :calculate, args: [:station_id]
    end

    resource Voria2.Measurements.Summaries.WindSummary do
      define :wind_summary, action: :calculate, args: [:station_id]
    end

    resource Voria2.Measurements.Summaries.RainSummary do
      define :rain_summary, action: :calculate, args: [:station_id]
    end
  end

  @doc """
  Recalculates summaries for a station after measurements are updated.
  Automatically refreshes all summary types (temperature, humidity/pressure, wind, rain).
  Returns :ok on success, {:error, reason} on failure.
  """
  def recalculate_summaries_for_station(station_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    try do
      temperature_summary(station_id,
        actor: actor,
        at: DateTime.utc_now(),
        offset_seconds: -3600
      )

      humidity_pressure_summary(station_id,
        actor: actor,
        at: DateTime.utc_now(),
        offset_seconds: -3600
      )

      wind_summary(station_id,
        actor: actor,
        at: DateTime.utc_now(),
        offset_seconds: -3600
      )

      rain_summary(station_id,
        actor: actor,
        at: DateTime.utc_now(),
        offset_seconds: -3600
      )

      :ok
    rescue
      e -> {:error, e}
    end
  end
end
