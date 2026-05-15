defmodule Voria2.Measurements.Summaries.HumidityPressureSummary do
  use Ash.Resource,
    otp_app: :voria2,
    domain: Voria2.Measurements

  resource do
    require_primary_key? false
  end

  actions do
    action :calculate, :struct do
      constraints instance_of: __MODULE__

      argument :station_id, :uuid, allow_nil?: false

      argument :at, :utc_datetime_usec do
        default &DateTime.utc_now/0
      end

      argument :offset_seconds, :integer do
        default -3600
      end

      run Voria2.Measurements.Summaries.HumidityPressureSummary.Calculate
    end
  end

  attributes do
    attribute :current_humidity, :float, public?: true
    attribute :humidity_trend, :atom, public?: true
    attribute :min_humidity_today, :map, public?: true
    attribute :max_humidity_today, :map, public?: true
    attribute :current_pressure, :float, public?: true
    attribute :pressure_trend, :atom, public?: true
    attribute :min_pressure_today, :map, public?: true
    attribute :max_pressure_today, :map, public?: true
    attribute :dewpoint, :float, public?: true
    attribute :barometer_trend, :atom, public?: true
  end
end
