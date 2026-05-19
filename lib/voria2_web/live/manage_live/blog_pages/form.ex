defmodule Voria2Web.ManageLive.BlogPages.Form do
  use Voria2Web, :live_view

  on_mount {Voria2Web.LiveUserAuth, :live_user_required}

  import Voria2Web.FlatpickrInputComponent

  @impl true
  def mount(params, _session, socket) do
    unless socket.assigns.current_user.admin do
      {:ok,
       socket
       |> put_flash(:error, gettext("Admin access required."))
       |> push_navigate(to: ~p"/manage")}
    else
      socket =
        socket
        |> assign(:active_section, :blog_pages)
        |> assign(:category_query, "")
        |> assign(:category_matches, list_categories(socket.assigns.current_user))

      socket =
        case socket.assigns.live_action do
          :new ->
            form =
              AshPhoenix.Form.for_create(
                Voria2.Blog.Article,
                :create,
                actor: socket.assigns.current_user,
                params: %{"publishing_date" => DateTime.to_iso8601(DateTime.utc_now())}
              )
              |> to_form()

            socket
            |> assign(:page_title, gettext("New Blog Page"))
            |> assign(:form, form)
            |> assign(:article, nil)
            |> assign(:selected_categories, [])

          :edit ->
            case Voria2.Blog.get_article(params["id"],
                   actor: socket.assigns.current_user,
                   load: [categories: [:name]]
                 ) do
              {:ok, article} ->
                form =
                  AshPhoenix.Form.for_update(
                    article,
                    :update,
                    actor: socket.assigns.current_user
                  )
                  |> to_form()

                socket
                |> assign(:page_title, gettext("Edit %{title}", title: article.title))
                |> assign(:form, form)
                |> assign(:article, article)
                |> assign(:selected_categories, Enum.sort_by(article.categories, &sort_name/1))

              {:error, _} ->
                socket
                |> put_flash(:error, gettext("Blog page not found."))
                |> push_navigate(to: ~p"/manage/blog_pages")
            end
        end

      {:ok, socket}
    end
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form =
      socket.assigns.form.source
      |> AshPhoenix.Form.validate(params_with_categories(socket, params))
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form.source,
           params: params_with_categories(socket, params)
         ) do
      {:ok, _article} ->
        message =
          if socket.assigns.live_action == :new,
            do: gettext("Blog page created."),
            else: gettext("Blog page updated.")

        {:noreply,
         socket
         |> put_flash(:info, message)
         |> push_navigate(to: ~p"/manage/blog_pages")}

      {:error, form} ->
        {:noreply, assign(socket, :form, form |> to_form())}
    end
  end

  def handle_event("delete_article", _params, socket) do
    case Voria2.Blog.destroy_article(socket.assigns.article, actor: socket.assigns.current_user) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Blog page deleted."))
         |> push_navigate(to: ~p"/manage/blog_pages")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to delete blog page."))}
    end
  end

  def handle_event("search_categories", %{"value" => value}, socket) do
    {:noreply,
     socket
     |> assign(:category_query, value)
     |> assign(:category_matches, search_categories(socket.assigns.current_user, value))}
  end

  def handle_event("select_category", %{"id" => id}, socket) do
    case find_category(socket.assigns.current_user, id) do
      nil ->
        {:noreply, socket}

      category ->
        {:noreply,
         socket
         |> assign(
           :selected_categories,
           merge_category(socket.assigns.selected_categories, category)
         )
         |> assign(:category_query, "")
         |> assign(:category_matches, list_categories(socket.assigns.current_user))}
    end
  end

  def handle_event("remove_category", %{"id" => id}, socket) do
    {:noreply,
     assign(
       socket,
       :selected_categories,
       Enum.reject(socket.assigns.selected_categories, &(&1.id == id))
     )}
  end

  def handle_event("create_category", _params, socket) do
    name = String.trim(socket.assigns.category_query)

    cond do
      name == "" ->
        {:noreply, socket}

      category = find_category_by_name(socket.assigns.current_user, name) ->
        {:noreply,
         socket
         |> assign(
           :selected_categories,
           merge_category(socket.assigns.selected_categories, category)
         )
         |> assign(:category_query, "")
         |> assign(:category_matches, list_categories(socket.assigns.current_user))}

      true ->
        case Voria2.Blog.create_category(%{name: name}, actor: socket.assigns.current_user) do
          {:ok, category} ->
            {:noreply,
             socket
             |> assign(
               :selected_categories,
               merge_category(socket.assigns.selected_categories, category)
             )
             |> assign(:category_query, "")
             |> assign(:category_matches, list_categories(socket.assigns.current_user))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Failed to create category."))}
        end
    end
  end

  @impl true
  def render(assigns) do
    body_errors = Voria2Web.CoreComponents.translate_errors(assigns.form.errors, :body)

    assigns =
      assigns
      |> assign(:body_errors, body_errors)
      |> assign(:can_create_category, can_create_category?(assigns))

    ~H"""
    <div class="w-full max-w-none space-y-5">
      <.breadcrumb crumbs={[
        {gettext("Blog Pages"), ~p"/manage/blog_pages"},
        {if(@live_action == :new, do: gettext("New Page"), else: @article.title), nil}
      ]} />

      <.header>
        {@page_title}
      </.header>

      <div>
        <.form
          for={@form}
          id="blog-page-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-6 pb-6"
        >
          <div class="grid gap-4 lg:grid-cols-2 xl:grid-cols-[minmax(0,1.35fr)_minmax(15rem,0.65fr)]">
            <.input
              field={@form[:title]}
              type="text"
              label={gettext("Title")}
              placeholder={gettext("Spring forecast update")}
            />
            <.input
              field={@form[:slug]}
              type="text"
              label={gettext("Slug")}
              placeholder="spring-forecast-update"
            />
            <div>
              <.input
                field={@form[:cover_image_url]}
                type="url"
                label={gettext("Cover Image URL")}
                placeholder="https://..."
              />
            </div>
            <div>
              <.input
                field={@form[:published]}
                type="select"
                label={gettext("Status")}
                options={publication_status_options()}
              />
            </div>
            <fieldset>
              <.datetime_picker
                id="blog-page-publishing-date"
                field_name={@form[:publishing_date].name}
                value={@form[:publishing_date].value}
                submit_mode={:utc_iso}
                label={gettext("Publishing Date")}
                placeholder="dd/mm/yyyy hh:mm"
                minute_increment={5}
                force_custom_mobile={true}
              />
            </fieldset>
          </div>

          <div class="space-y-2">
            <div>
              <h3 class="text-sm font-semibold uppercase tracking-[0.16em] text-base-content/60">
                {gettext("Body")}
              </h3>
            </div>

            <div
              id="blog-page-body-editor"
              phx-hook="HugeRteInput"
              phx-update="ignore"
              data-input-id={@form[:body].id}
              data-editor-id={"#{@form[:body].id}-editor-input"}
              class="space-y-2"
            >
              <textarea id={@form[:body].id} name={@form[:body].name} class="hidden">{Phoenix.HTML.Form.normalize_value("textarea", @form[:body].value)}</textarea>
              <textarea id={"#{@form[:body].id}-editor-input"} class="min-h-[32rem] w-full textarea"></textarea>
            </div>

            <p :for={msg <- @body_errors} class="flex items-center gap-2 text-sm text-error">
              <.icon name="hero-exclamation-circle" class="size-5" />
              {msg}
            </p>
          </div>

          <div class="border border-base-300 bg-base-100 divide-y divide-base-300 overflow-hidden">
            <div class="px-5 py-3.5 bg-base-200/40">
              <h3 class="text-sm font-semibold">{gettext("Categories")}</h3>
            </div>
            <div class="px-5 py-4 space-y-4">
              <div class="space-y-3">
                <label class="input input-bordered flex items-center gap-2">
                  <.icon name="hero-magnifying-glass" class="size-4 text-base-content/40" />
                  <input
                    id="blog-page-category-query"
                    type="text"
                    name="category_query"
                    value={@category_query}
                    placeholder={gettext("Search or add a category...")}
                    phx-keyup="search_categories"
                    phx-debounce="200"
                  />
                </label>

                <div class="flex min-h-8 flex-wrap gap-2">
                  <button
                    :for={category <- @selected_categories}
                    type="button"
                    phx-click="remove_category"
                    phx-value-id={category.id}
                    class="badge badge-primary badge-lg gap-2 px-3 py-3"
                  >
                    <span>{category.name}</span>
                    <.icon name="hero-x-mark" class="size-3.5" />
                  </button>
                  <span :if={@selected_categories == []} class="text-sm text-base-content/50">
                    {gettext("No categories selected yet.")}
                  </span>
                </div>
              </div>

              <div class="space-y-2">
                <button
                  :if={@can_create_category}
                  id="blog-page-create-category"
                  type="button"
                  phx-click="create_category"
                  class="btn btn-soft btn-sm w-full justify-start gap-2"
                >
                  <.icon name="hero-plus" class="size-4" />
                  {gettext("Add \"%{name}\"", name: String.trim(@category_query))}
                </button>

                <div class="border border-base-300 bg-base-100 max-h-72 overflow-y-auto divide-y divide-base-300">
                  <button
                    :for={
                      category <-
                        available_category_matches(@selected_categories, @category_matches)
                    }
                    id={"blog-page-category-option-#{category.id}"}
                    type="button"
                    phx-click="select_category"
                    phx-value-id={category.id}
                    class="w-full px-4 py-3 text-left hover:bg-base-200/70 transition-colors"
                  >
                    <div class="font-medium text-sm">{category.name}</div>
                  </button>
                  <div
                    :if={
                      available_category_matches(@selected_categories, @category_matches) == [] &&
                        !@can_create_category
                    }
                    class="px-4 py-6 text-center text-sm text-base-content/50"
                  >
                    {gettext("No matching categories.")}
                  </div>
                </div>
              </div>
            </div>
          </div>

          <div :if={@live_action == :edit} class="border border-error/30 bg-error/5 overflow-hidden">
            <div class="px-5 py-4 space-y-3">
              <div>
                <h3 class="text-sm font-semibold text-error">{gettext("Danger Zone")}</h3>
                <p class="text-sm text-base-content/60 mt-1">
                  {gettext("Delete this blog page permanently.")}
                </p>
              </div>
              <button
                type="button"
                class="btn btn-ghost btn-sm text-error hover:bg-error/10 gap-2"
                onclick="document.getElementById('delete-blog-page').showModal()"
              >
                <.icon name="hero-trash" class="size-4" /> {gettext("Delete Blog Page")}
              </button>
            </div>
          </div>

          <div class="flex justify-between gap-3">
            <.link navigate={~p"/manage/blog_pages"} class="btn btn-ghost btn-sm">
              {gettext("Cancel")}
            </.link>
            <.button type="submit" variant="primary">
              {if @live_action == :new, do: gettext("Create Page"), else: gettext("Save Changes")}
            </.button>
          </div>
        </.form>
      </div>

      <.confirm_modal
        :if={@live_action == :edit}
        id="delete-blog-page"
        title={gettext("Delete %{title}?", title: @article.title)}
        message={gettext("This blog page will be permanently removed.")}
        confirm_label={gettext("Delete")}
        confirm_event="delete_article"
        confirm_value={%{}}
        danger={true}
      />
    </div>
    """
  end

  defp params_with_categories(socket, params) do
    Map.put(params, "category_ids", Enum.map(socket.assigns.selected_categories, & &1.id))
  end

  defp list_categories(actor) do
    Voria2.Blog.list_categories!(actor: actor)
    |> Enum.sort_by(&sort_name/1)
  end

  defp search_categories(actor, query) do
    case Voria2.Blog.search_categories(query, actor: actor) do
      {:ok, categories} -> Enum.sort_by(categories, &sort_name/1)
      {:error, _} -> []
    end
  end

  defp find_category(actor, id) do
    case Voria2.Blog.get_category(id, actor: actor) do
      {:ok, category} -> category
      {:error, _} -> nil
    end
  end

  defp find_category_by_name(actor, name) do
    case Voria2.Blog.find_category_by_name(name, actor: actor) do
      {:ok, category} -> category
      {:error, _} -> nil
    end
  end

  defp merge_category(categories, category) do
    categories
    |> Enum.reject(&(&1.id == category.id))
    |> Kernel.++([category])
    |> Enum.sort_by(&sort_name/1)
  end

  defp available_category_matches(selected_categories, matches) do
    selected_ids = MapSet.new(Enum.map(selected_categories, & &1.id))
    Enum.reject(matches, &MapSet.member?(selected_ids, &1.id))
  end

  defp can_create_category?(assigns) do
    trimmed_query = String.trim(assigns.category_query)

    trimmed_query != "" and
      Enum.all?(
        assigns.selected_categories,
        &(String.downcase(to_string(&1.name)) != String.downcase(trimmed_query))
      ) and
      Enum.all?(
        assigns.category_matches,
        &(String.downcase(to_string(&1.name)) != String.downcase(trimmed_query))
      )
  end

  defp publication_status_options do
    [
      {gettext("Draft"), false},
      {gettext("Published"), true}
    ]
  end

  defp sort_name(category), do: String.downcase(to_string(category.name))
end
