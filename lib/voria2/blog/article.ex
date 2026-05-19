defmodule Voria2.Blog.Article do
  use Ash.Resource,
    otp_app: :voria2,
    domain: Voria2.Blog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "blog_articles"
    repo Voria2.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:title, :slug, :body, :cover_image_url, :published, :publishing_date]

      argument :category_ids, {:array, :uuid} do
        allow_nil? true
        default []
      end

      change manage_relationship(:category_ids, :categories,
               type: :append_and_remove,
               on_lookup: :relate,
               value_is_key: :id
             )
    end

    update :update do
      primary? true
      require_atomic? false
      accept [:title, :slug, :body, :cover_image_url, :published, :publishing_date]

      argument :category_ids, {:array, :uuid} do
        allow_nil? true
        default []
      end

      change manage_relationship(:category_ids, :categories,
               type: :append_and_remove,
               on_lookup: :relate,
               value_is_key: :id
             )
    end

    destroy :destroy do
      primary? true
    end
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(published == true and publishing_date <= now())
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
      constraints min_length: 1
    end

    attribute :slug, :string do
      allow_nil? false
      public? true
      constraints min_length: 1
    end

    attribute :body, :string do
      allow_nil? false
      public? true
      constraints min_length: 1
    end

    attribute :cover_image_url, :string do
      public? true
    end

    attribute :published, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :publishing_date, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
      public? true
    end

    timestamps()
  end

  relationships do
    many_to_many :categories, Voria2.Blog.Category do
      through Voria2.Blog.ArticleCategory
      source_attribute_on_join_resource :article_id
      destination_attribute_on_join_resource :category_id
      public? true
    end
  end

  identities do
    identity :unique_slug, [:slug]
  end
end
