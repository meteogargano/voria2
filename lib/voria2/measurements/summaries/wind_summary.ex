defmodule Voria2.Measurements.Summaries.WindSummary do
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

      run Voria2.Measurements.Summaries.WindSummary.Calculate
    end
  end

  attributes do
    attribute :current_speed, :float, public?: true
    attribute :current_direction, :float, public?: true
    attribute :current_gust, :float, public?: true
    attribute :max_gust_today, :map, public?: true
    attribute :wind_rose, {:array, :map}, public?: true
  end
end
