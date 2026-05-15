defmodule Voria2.Blog.ArticleCategory do
  use Ash.Resource,
    otp_app: :voria2,
    domain: Voria2.Blog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "blog_article_categories"
    repo Voria2.Repo

    references do
      reference :article, on_delete: :delete
      reference :category, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy, create: :*]
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

    timestamps()
  end

  relationships do
    belongs_to :article, Voria2.Blog.Article do
      allow_nil? false
      public? true
    end

    belongs_to :category, Voria2.Blog.Category do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_article_category, [:article_id, :category_id]
  end
end
