defmodule Voria2.Network.Installation do
  use Ash.Resource,
    otp_app: :voria2,
    domain: Voria2.Network,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "installations"
    repo Voria2.Repo
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    update :add_picture do
      require_atomic? false
      argument :picture_key, :string, allow_nil?: false

      change fn changeset, _ ->
        key = Ash.Changeset.get_argument(changeset, :picture_key)
        current = changeset.data.picture_keys || []
        Ash.Changeset.force_change_attribute(changeset, :picture_keys, current ++ [key])
      end
    end

    update :remove_picture do
      require_atomic? false
      argument :picture_key, :string, allow_nil?: false

      change fn changeset, _ ->
        key = Ash.Changeset.get_argument(changeset, :picture_key)
        current = changeset.data.picture_keys || []
        Ash.Changeset.force_change_attribute(changeset, :picture_keys, List.delete(current, key))
      end
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

    attribute :description, :string do
      public? true
    end

    attribute :latitude, :float do
      allow_nil? false
      public? true
    end

    attribute :longitude, :float do
      allow_nil? false
      public? true
    end

    attribute :altitude, :float do
      public? true
    end

    attribute :timezone, :string do
      public? true
    end

    attribute :country, :string do
      public? true
    end

    attribute :city, :string do
      public? true
    end

    attribute :picture_keys, {:array, :string} do
      public? true
      default []
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
      allow_nil? false
      public? true
    end

    has_many :stations, Voria2.Network.Station
    has_many :webcams, Voria2.Network.Webcam
  end

  identities do
    identity :unique_name_per_user, [:user_id, :name]
  end
end
