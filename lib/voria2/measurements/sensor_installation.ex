defmodule Voria2.Measurements.SensorInstallation do
  use Ash.Resource,
    otp_app: :voria2,
    domain: Voria2.Measurements,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "sensor_installations"
    repo Voria2.Repo

    references do
      reference :station, on_delete: :delete
    end
  end

  actions do
    defaults [:read, create: :*]

    destroy :destroy do
      primary? true
      require_atomic? false
      change Voria2.Measurements.SensorInstallation.Changes.InvalidateCache
    end

    update :update do
      primary? true
      require_atomic? false
      accept [:installed_at, :removed_at, :model, :notes, :rain_mode]
      change Voria2.Measurements.SensorInstallation.Changes.InvalidateCache
    end

    update :decommission do
      accept []
      require_atomic? false
      change set_attribute(:removed_at, &Date.utc_today/0)
      change Voria2.Measurements.SensorInstallation.Changes.InvalidateCache
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

    policy action_type(:update) do
      authorize_if relates_to_actor_via([:station, :installation, :user])
    end

    policy action_type(:destroy) do
      authorize_if relates_to_actor_via([:station, :installation, :user])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :installed_at, :date do
      allow_nil? false
      public? true
    end

    attribute :removed_at, :date do
      public? true
    end

    attribute :model, :string do
      public? true
    end

    attribute :notes, :string do
      public? true
    end

    attribute :rain_mode, :atom do
      public? true
      constraints one_of: [:interval, :cumulative]
    end

    timestamps()
  end

  relationships do
    belongs_to :station, Voria2.Network.Station do
      allow_nil? false
      public? true
    end

    belongs_to :measurement_type, Voria2.Measurements.MeasurementType do
      allow_nil? false
      public? true
    end
  end

  calculations do
    calculate :is_active, :boolean, expr(is_nil(removed_at))
  end
end
