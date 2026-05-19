defmodule Voria2.Repo.Migrations.AddPublishingDateToBlogArticles do
  use Ecto.Migration

  def up do
    alter table(:blog_articles) do
      add :publishing_date, :utc_datetime_usec
    end

    execute(
      "UPDATE blog_articles SET publishing_date = inserted_at WHERE publishing_date IS NULL"
    )

    execute(
      "ALTER TABLE blog_articles ALTER COLUMN publishing_date SET DEFAULT (now() AT TIME ZONE 'utc')",
      "ALTER TABLE blog_articles ALTER COLUMN publishing_date DROP DEFAULT"
    )

    execute(
      "ALTER TABLE blog_articles ALTER COLUMN publishing_date SET NOT NULL",
      "ALTER TABLE blog_articles ALTER COLUMN publishing_date DROP NOT NULL"
    )

    create index(:blog_articles, [:published, :publishing_date],
             name: "blog_articles_published_publishing_date_index"
           )
  end

  def down do
    drop_if_exists index(:blog_articles, [:published, :publishing_date],
                     name: "blog_articles_published_publishing_date_index"
                   )

    alter table(:blog_articles) do
      remove :publishing_date
    end
  end
end
