defmodule Voria2.Measurements.RainMeasurement do
  use Ash.Resource,
    otp_app: :voria2,
    domain: Voria2.Measurements,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "rain_measurements"
    repo Voria2.Repo

    references do
      reference :sensor_installation, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :record_interval do
      description "Record rain as a direct fixed-interval accumulation (mm)"
      accept [:sensor_installation_id, :measured_at, :interval_mm]

      validate compare(:interval_mm, greater_than_or_equal_to: 0.0) do
        message "rain accumulation cannot be negative"
      end

      change Voria2.Measurements.Changes.RoundFloatPrecisionRain
    end

    create :record_cumulative do
      description "Record rain from a cumulative-count sensor; interval is computed automatically"
      accept [:sensor_installation_id, :measured_at]

      argument :cumulative_value, :float do
        allow_nil? false
      end

      change Voria2.Measurements.RainMeasurement.Changes.ComputeIntervalFromCumulative
      change Voria2.Measurements.Changes.RoundFloatPrecisionRain
    end

    update :update do
      accept [:measured_at, :interval_mm]
      require_atomic? false

      validate compare(:interval_mm, greater_than_or_equal_to: 0.0) do
        message "rain accumulation cannot be negative"
      end

      change Voria2.Measurements.Changes.RoundFloatPrecisionRain
    end

    read :for_sensor do
      argument :sensor_installation_id, :uuid, allow_nil?: false
      argument :from, :utc_datetime_usec, allow_nil?: false
      argument :to, :utc_datetime_usec, allow_nil?: false

      filter expr(
               sensor_installation_id == ^arg(:sensor_installation_id) and
                 measured_at >= ^arg(:from) and
                 measured_at <= ^arg(:to)
             )

      prepare build(sort: [measured_at: :asc])
    end
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy action_type(:destroy) do
      authorize_if relates_to_actor_via([:sensor_installation, :station, :installation, :user])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :measured_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    # Always stored as a fixed-interval accumulation in mm (0.0 = no rain)
    attribute :interval_mm, :float do
      allow_nil? false
      public? true
      default 0.0
    end
  end

  relationships do
    belongs_to :sensor_installation, Voria2.Measurements.SensorInstallation do
      allow_nil? false
      public? true
    end
  end
end
