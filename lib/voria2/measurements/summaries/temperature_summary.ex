defmodule Voria2.Measurements.Summaries.TemperatureSummary do
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

      run Voria2.Measurements.Summaries.TemperatureSummary.Calculate
    end
  end

  attributes do
    attribute :current, :float, public?: true
    attribute :trend, :atom, public?: true
    attribute :min_today, :map, public?: true
    attribute :max_today, :map, public?: true
    attribute :diff_24h, :float, public?: true
    attribute :history, {:array, :map}, public?: true
  end
end
