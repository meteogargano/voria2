defmodule Voria2.Blog.Category do
  use Ash.Resource,
    otp_app: :voria2,
    domain: Voria2.Blog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "blog_categories"
    repo Voria2.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:name]
    end

    read :by_name do
      argument :name, :ci_string, allow_nil?: false
      get? true
      filter expr(name == ^arg(:name))
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
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :ci_string do
      allow_nil? false
      public? true
      constraints min_length: 1
    end

    timestamps()
  end

  relationships do
    many_to_many :articles, Voria2.Blog.Article do
      through Voria2.Blog.ArticleCategory
      source_attribute_on_join_resource :category_id
      destination_attribute_on_join_resource :article_id
    end
  end

  identities do
    identity :unique_name, [:name]
  end
end
