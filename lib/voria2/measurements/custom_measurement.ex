defmodule Voria2.Measurements.CustomMeasurement do
  use Ash.Resource,
    otp_app: :voria2,
    domain: Voria2.Measurements,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "custom_measurements"
    repo Voria2.Repo

    references do
      reference :sensor_installation, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :record do
      accept [:sensor_installation_id, :measurement_type_id, :measured_at, :value, :raw]
      upsert? true
      upsert_identity :unique_sensor_timestamp
      upsert_fields [:value, :raw]

      change Voria2.Measurements.Changes.RoundFloatPrecision
    end

    update :update do
      accept [:measured_at, :value, :raw]
      require_atomic? false

      change Voria2.Measurements.Changes.RoundFloatPrecision
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

    attribute :value, :float do
      public? true
    end

    attribute :raw, :map do
      public? true
    end
  end

  relationships do
    belongs_to :sensor_installation, Voria2.Measurements.SensorInstallation do
      allow_nil? false
      public? true
    end

    belongs_to :measurement_type, Voria2.Measurements.MeasurementType do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_sensor_timestamp, [:sensor_installation_id, :measured_at]
  end
end
