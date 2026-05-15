defmodule Voria2.Network.WebcamApiKey do
  use Ash.Resource,
    otp_app: :voria2,
    domain: Voria2.Network,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "webcam_api_keys"
    repo Voria2.Repo
  end

  actions do
    defaults [:read]

    create :generate do
      accept [:webcam_id, :label]

      change fn changeset, _ ->
        key = "vwk_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
        Ash.Changeset.force_change_attribute(changeset, :key, key)
      end
    end

    destroy :revoke do
      primary? true
      require_atomic? false
      change Voria2.Network.WebcamApiKey.Changes.InvalidateCache
    end

    read :by_key do
      argument :key, :string, allow_nil?: false
      get? true
      filter expr(key == ^arg(:key))
    end
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    policy action(:by_key) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if relates_to_actor_via([:webcam, :installation, :user])
    end

    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy action_type(:destroy) do
      authorize_if relates_to_actor_via([:webcam, :installation, :user])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :key, :string do
      allow_nil? false
      public? true
    end

    attribute :label, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :webcam, Voria2.Network.Webcam do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_key, [:key]
  end
end
