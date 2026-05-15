defmodule Voria2.Network.WebcamShot do
  use Ash.Resource,
    otp_app: :voria2,
    domain: Voria2.Network,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "webcam_shots"
    repo Voria2.Repo

    custom_indexes do
      index [:original_hash], unique: true
      index [:webcam_id, :captured_at]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :record do
      accept [
        :webcam_id,
        :captured_at,
        :s3_key,
        :s3_bucket,
        :original_hash,
        :width,
        :height,
        :file_size_bytes,
        :metadata
      ]
    end

    read :by_hash do
      argument :hash, :string, allow_nil?: false
      get? true
      filter expr(original_hash == ^arg(:hash))
    end

    read :latest_for_webcam do
      argument :webcam_id, :uuid, allow_nil?: false
      filter expr(webcam_id == ^arg(:webcam_id))
      prepare build(sort: [captured_at: :desc], limit: 1)
    end

    read :history do
      argument :webcam_id, :uuid, allow_nil?: false
      argument :from, :utc_datetime_usec, allow_nil?: false
      argument :to, :utc_datetime_usec, allow_nil?: false

      filter expr(
               webcam_id == ^arg(:webcam_id) and
                 captured_at >= ^arg(:from) and
                 captured_at <= ^arg(:to)
             )

      prepare build(sort: [captured_at: :desc])
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
      authorize_if relates_to_actor_via([:webcam, :installation, :user])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :captured_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :s3_key, :string do
      allow_nil? false
      public? true
    end

    attribute :s3_bucket, :string do
      allow_nil? false
      public? true
    end

    attribute :original_hash, :string do
      allow_nil? false
      public? true
    end

    attribute :width, :integer do
      public? true
    end

    attribute :height, :integer do
      public? true
    end

    attribute :file_size_bytes, :integer do
      public? true
    end

    attribute :metadata, :map do
      public? true
      default %{}
    end

    timestamps()
  end

  relationships do
    belongs_to :webcam, Voria2.Network.Webcam do
      allow_nil? false
      public? true
    end
  end
end
