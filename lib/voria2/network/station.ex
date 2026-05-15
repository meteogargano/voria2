defmodule Voria2.Network.Station do
  use Ash.Resource,
    otp_app: :voria2,
    domain: Voria2.Network,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "stations"
    repo Voria2.Repo
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
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
      authorize_if relates_to_actor_via([:installation, :user])
    end

    policy action_type(:destroy) do
      authorize_if relates_to_actor_via([:installation, :user])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints min_length: 1
    end

    attribute :slug, :string do
      allow_nil? false
      public? true
      constraints min_length: 1
    end

    attribute :description, :string do
      public? true
    end

    attribute :is_active, :boolean do
      allow_nil? false
      default true
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :installation, Voria2.Network.Installation do
      allow_nil? false
      public? true
    end

    has_many :sensor_installations, Voria2.Measurements.SensorInstallation
  end

  identities do
    identity :unique_slug, [:slug]
  end
end
