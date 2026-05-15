defmodule Voria2.Measurements.RainCumulativeState do
  @moduledoc """
  Tracks the last cumulative reading per sensor installation for rain sensors
  configured with `rain_mode: :cumulative`. Used to compute interval_mm.
  """

  use Ash.Resource,
    otp_app: :voria2,
    domain: Voria2.Measurements,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "rain_cumulative_states"
    repo Voria2.Repo

    references do
      reference :sensor_installation, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :upsert do
      accept [:sensor_installation_id, :last_cumulative_value, :last_updated_at]
      upsert? true
      upsert_identity :unique_sensor
      upsert_fields [:last_cumulative_value, :last_updated_at]
    end

    read :for_sensor do
      argument :sensor_installation_id, :uuid, allow_nil?: false
      get? true
      filter expr(sensor_installation_id == ^arg(:sensor_installation_id))
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
  end

  attributes do
    uuid_primary_key :id

    attribute :last_cumulative_value, :float do
      allow_nil? false
      public? true
    end

    attribute :last_updated_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :sensor_installation, Voria2.Measurements.SensorInstallation do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_sensor, [:sensor_installation_id]
  end
end
