defmodule Voria2Web.ManageLive.BlogPages.Index do
  use Voria2Web, :live_view

  on_mount {Voria2Web.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    unless socket.assigns.current_user.admin do
      {:ok,
       socket
       |> put_flash(:error, gettext("Admin access required."))
       |> push_navigate(to: ~p"/manage")}
    else
      {:ok,
       socket
       |> assign(:page_title, gettext("Blog Pages"))
       |> assign(:active_section, :blog_pages)
       |> assign(:articles, list_articles(socket.assigns.current_user))}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case Voria2.Blog.get_article(id,
           actor: socket.assigns.current_user,
           load: [:categories]
         ) do
      {:ok, article} ->
        case Voria2.Blog.destroy_article(article, actor: socket.assigns.current_user) do
          :ok ->
            {:noreply,
             socket
             |> put_flash(:info, gettext("Blog page deleted."))
             |> assign(:articles, list_articles(socket.assigns.current_user))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Failed to delete blog page."))}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Blog page not found."))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl">
      <.breadcrumb crumbs={[{gettext("Blog Pages"), nil}]} />

      <.header>
        {gettext("Blog Pages")}
        <:subtitle>
          {gettext("Create, publish, and organize blog pages with reusable categories.")}
        </:subtitle>
        <:actions>
          <.link navigate={~p"/manage/blog_pages/new"} class="btn btn-primary btn-sm gap-2">
            <.icon name="hero-plus" class="size-4" /> {gettext("New Page")}
          </.link>
        </:actions>
      </.header>

      <div class="mt-4">
        <.resource_table
          id="blog-pages-table"
          rows={@articles}
          empty_title={gettext("No blog pages yet")}
          empty_message={gettext("Create your first blog page to start publishing content.")}
          empty_icon="hero-newspaper"
        >
          <:empty_actions>
            <.link navigate={~p"/manage/blog_pages/new"} class="btn btn-primary btn-sm gap-2">
              <.icon name="hero-plus" class="size-4" /> {gettext("New Page")}
            </.link>
          </:empty_actions>
          <:col :let={article} label={gettext("Title")}>
            <div class="space-y-1">
              <div class="font-medium">{article.title}</div>
              <code class="text-xs font-mono text-base-content/50">{article.slug}</code>
            </div>
          </:col>
          <:col :let={article} label={gettext("Categories")}>
            <div class="flex flex-wrap gap-1">
              <span
                :for={category <- article.categories}
                class="badge badge-sm badge-ghost"
              >
                {category.name}
              </span>
              <span :if={article.categories == []} class="text-sm text-base-content/50">—</span>
            </div>
          </:col>
          <:col :let={article} label={gettext("Status")}>
            <.status_badge
              active={article.published}
              active_label={gettext("Published")}
              inactive_label={gettext("Draft")}
            />
          </:col>
          <:col :let={article} label={gettext("Publishing Date")}>
            <span class="text-sm text-base-content/60">{format_date(article.publishing_date)}</span>
          </:col>
          <:action :let={article}>
            <.link
              navigate={~p"/manage/blog_pages/#{article.id}/edit"}
              class="btn btn-ghost btn-xs"
            >
              <.icon name="hero-pencil" class="size-3.5" />
            </.link>
            <button
              class="btn btn-ghost btn-xs text-error hover:bg-error/10"
              onclick={"document.getElementById('del-blog-page-#{article.id}').showModal()"}
            >
              <.icon name="hero-trash" class="size-3.5" />
            </button>
            <.confirm_modal
              id={"del-blog-page-#{article.id}"}
              title={gettext("Delete %{title}?", title: article.title)}
              message={gettext("This blog page will be permanently removed.")}
              confirm_label={gettext("Delete")}
              confirm_event="delete"
              confirm_value={%{id: article.id}}
              danger={true}
            />
          </:action>
        </.resource_table>
      </div>
    </div>
    """
  end

  defp list_articles(actor) do
    Voria2.Blog.list_articles!(actor: actor, load: [categories: [:name]])
  end

  defp format_date(nil), do: "—"

  defp format_date(value) do
    Calendar.strftime(value, "%Y-%m-%d %H:%M")
  end
end
