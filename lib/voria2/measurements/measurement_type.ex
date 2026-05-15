defmodule Voria2.Measurements.MeasurementType do
  use Ash.Resource,
    otp_app: :voria2,
    domain: Voria2.Measurements,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "measurement_types"
    repo Voria2.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:name, :slug, :unit, :storage_type, :description]
      change {Ash.Resource.Change.RelateActor, relationship: :user, allow_nil?: true}
    end

    update :update do
      accept [:name, :unit, :description, :is_active]
      require_atomic? false
      change Voria2.Measurements.MeasurementType.Changes.PreventSystemUnitChange
    end

    destroy :destroy do
      primary? true
    end
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # Anyone can read measurement types
    policy action_type(:read) do
      authorize_if always()
    end

    # Authenticated users can create user-defined types
    policy action_type(:create) do
      authorize_if actor_present()
    end

    # Only owners can update/destroy their user-defined types
    policy action_type(:update) do
      authorize_if relates_to_actor_via(:user)
    end

    policy action_type(:destroy) do
      authorize_if relates_to_actor_via(:user)
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

    attribute :unit, :string do
      public? true
    end

    attribute :storage_type, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:scalar, :wind, :rain, :custom]
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
    belongs_to :user, Voria2.Accounts.User do
      allow_nil? true
      public? true
    end
  end

  calculations do
    calculate :is_system_defined, :boolean, expr(is_nil(user_id))
  end

  identities do
    identity :unique_slug, [:slug]
  end
end
