defmodule Voria2.Measurements.WindMeasurement do
  use Ash.Resource,
    otp_app: :voria2,
    domain: Voria2.Measurements,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "wind_measurements"
    repo Voria2.Repo

    references do
      reference :sensor_installation, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :record do
      accept [:sensor_installation_id, :measured_at, :u, :v, :gust]
      upsert? true
      upsert_identity :unique_sensor_timestamp
      upsert_fields [:u, :v, :gust]

      change Voria2.Measurements.Changes.RoundFloatPrecisionWind
    end

    update :update do
      accept [:measured_at, :u, :v, :gust]
      require_atomic? false

      change Voria2.Measurements.Changes.RoundFloatPrecisionWind
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

    # Eastward wind component (m/s); positive = from west
    attribute :u, :float do
      allow_nil? false
      public? true
    end

    # Northward wind component (m/s); positive = from south
    attribute :v, :float do
      allow_nil? false
      public? true
    end

    # Peak gust (m/s); nil when sensor does not provide it
    attribute :gust, :float do
      public? true
    end
  end

  relationships do
    belongs_to :sensor_installation, Voria2.Measurements.SensorInstallation do
      allow_nil? false
      public? true
    end
  end

  calculations do
    # Scalar wind speed from vector components
    calculate :speed, :float, expr(fragment("sqrt(? * ? + ? * ?)", u, u, v, v))

    # Meteorological direction: 0° = N, 90° = E, 180° = S, 270° = W
    # atan2 in SQL returns radians; we convert and apply meteorological convention
    calculate :direction_deg,
              :float,
              expr(
                fragment(
                  "mod((DEGREES(ATAN2(?, ?)) + 180.0)::numeric, 360.0)::float8",
                  u,
                  v
                )
              )
  end

  identities do
    identity :unique_sensor_timestamp, [:sensor_installation_id, :measured_at]
  end
end
