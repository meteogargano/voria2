defmodule Voria2.Measurements.Summaries.RainSummary do
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

      run Voria2.Measurements.Summaries.RainSummary.Calculate
    end
  end

  attributes do
    attribute :total_today, :float, public?: true
    attribute :instant_rain, :float, public?: true
    attribute :rain_rate, :float, public?: true
    attribute :days_without_rain, :integer, public?: true
  end
end
