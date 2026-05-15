defmodule Voria2Web.ManageLive.Installations.Photos do
  use Voria2Web, :live_view

  on_mount {Voria2Web.LiveUserAuth, :live_user_required}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Voria2.Network.get_installation(id, actor: socket.assigns.current_user) do
      {:ok, installation} ->
        socket =
          socket
          |> assign(:page_title, installation.name)
          |> assign(:active_section, :installations)
          |> assign(:installation, installation)
          |> allow_upload(:photos,
            accept: ~w(.jpg .jpeg .png .gif .webp),
            max_file_size: 10_000_000,
            max_entries: 10,
            auto_upload: true,
            progress: &handle_progress/3
          )

        {:ok, socket}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Installation not found."))
         |> push_navigate(to: ~p"/manage/installations")}
    end
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photos, ref)}
  end

  @impl true
  def handle_event("delete_photo", %{"picture_key" => picture_key}, socket) do
    bucket = Application.get_env(:voria2, :storage_bucket, "voria2-media")
    thumb_key = Voria2.InstallationIngest.thumbnail_key(picture_key)

    with :ok <- Voria2.Storage.delete(picture_key, bucket),
         :ok <- Voria2.Storage.delete(thumb_key, bucket),
         {:ok, _updated} <-
           Voria2.Network.remove_installation_picture(
             socket.assigns.installation,
             picture_key,
             actor: socket.assigns.current_user
           ) do
      {:ok, reloaded} = Voria2.Network.get_installation(socket.assigns.installation.id)

      {:noreply,
       socket
       |> assign(:installation, reloaded)
       |> put_flash(:info, gettext("Photo deleted."))}
    else
      {:error, reason} when is_binary(reason) ->
        {:noreply,
         put_flash(socket, :error, gettext("Failed to delete photo: %{reason}", reason: reason))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to delete photo."))}
    end
  end

  def handle_progress(:photos, entry, socket) do
    if entry.done? do
      result =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          case File.read(path) do
            {:ok, binary} ->
              Voria2.InstallationIngest.process(
                socket.assigns.installation,
                binary,
                socket.assigns.current_user
              )

            {:error, _reason} ->
              {:error, :file_read_failed}
          end
        end)

      case result do
        {:ok, updated} when is_struct(updated) ->
          {:ok, reloaded} = Voria2.Network.get_installation(socket.assigns.installation.id)

          {:noreply,
           socket
           |> assign(:installation, reloaded)
           |> put_flash(:info, gettext("Photo uploaded successfully."))}

        {:ok, {:duplicate, _key}} ->
          {:ok, reloaded} = Voria2.Network.get_installation(socket.assigns.installation.id)

          {:noreply,
           socket
           |> assign(:installation, reloaded)
           |> put_flash(:info, gettext("Photo already exists."))}

        {:ok, {:error, reason}} ->
          {:noreply,
           socket
           |> put_flash(
             :error,
             gettext("Failed to process %{name}: %{reason}",
               name: entry.client_name,
               reason: inspect(reason)
             )
           )}

        {:error, reason} ->
          {:noreply,
           socket
           |> put_flash(
             :error,
             gettext("Failed to upload %{name}: %{reason}",
               name: entry.client_name,
               reason: inspect(reason)
             )
           )}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl">
      <.breadcrumb crumbs={[
        {gettext("Installations"), ~p"/manage/installations"},
        {@installation.name, ~p"/manage/installations/#{@installation.id}"},
        {gettext("Photos"), nil}
      ]} />

      <.header>
        {gettext("%{name} - Photos", name: @installation.name)}
        <:subtitle>
          {gettext("Manage photos for this installation")}
        </:subtitle>
        <:actions>
          <.link navigate={~p"/manage/installations/#{@installation.id}"} class="btn btn-ghost btn-sm">
            {gettext("Back")}
          </.link>
        </:actions>
      </.header>

      <div class="mt-4 space-y-6">
        <%!-- Upload Section --%>
        <div class="card bg-base-200 border border-base-300">
          <div class="card-body p-6">
            <h2 class="card-title text-base">{gettext("Upload Photos")}</h2>

            <form phx-change="validate" id="upload-form">
              <div
                class={[
                  "border-2 border-dashed  p-8 text-center transition-colors relative",
                  if(@uploads.photos.entries == [],
                    do: "border-base-300 hover:border-primary",
                    else: "border-primary bg-primary/5"
                  )
                ]}
                phx-drop-target={@uploads.photos.ref}
              >
                <div class="space-y-3 pointer-events-none relative z-10">
                  <div class="size-12 rounded-full bg-primary/10 flex items-center justify-center mx-auto">
                    <.icon name="hero-cloud-arrow-up" class="size-6 text-primary" />
                  </div>
                  <div>
                    <p class="font-semibold text-base-content">
                      {gettext("Drop photos here or click to browse")}
                    </p>
                    <p class="text-sm text-base-content/60 mt-1">
                      {gettext("JPG, PNG, GIF, WebP up to 10MB each")}
                    </p>
                  </div>
                  <button
                    type="button"
                    class="btn btn-primary btn-sm pointer-events-none"
                  >
                    {gettext("Choose Files")}
                  </button>
                </div>

                <.live_file_input upload={@uploads.photos} class="absolute inset-0 opacity-0 z-20" />
              </div>
            </form>

            <div :if={@uploads.photos.entries != []} class="mt-4 space-y-2">
              <h3 class="text-sm font-semibold text-base-content/70">{gettext("Uploading...")}</h3>
              <%= for entry <- @uploads.photos.entries do %>
                <div class="flex items-center gap-3 p-2 rounded-lg bg-base-300/30">
                  <div class="flex-1 min-w-0">
                    <p class="text-sm font-medium truncate">{entry.client_name}</p>
                    <p class="text-xs text-base-content/60">
                      {format_bytes(entry.client_size)}
                    </p>
                  </div>
                  <div class="flex items-center gap-2">
                    <%= if entry.progress do %>
                      <div
                        class="radial-progress radial-progress-sm text-primary"
                        style={"--value:#{entry.progress}%; --size:1.5rem"}
                      >
                        {trunc(entry.progress)}%
                      </div>
                      <button
                        type="button"
                        class="btn btn-circle btn-xs btn-ghost"
                        phx-click="cancel_upload"
                        phx-value-ref={entry.ref}
                      >
                        <.icon name="hero-x-mark" class="size-3" />
                      </button>
                    <% else %>
                      <span class="loading loading-spinner loading-sm"></span>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <%!-- Photos Grid --%>
        <div class="card bg-base-200 border border-base-300">
          <div class="card-body p-6">
            <div class="flex items-center justify-between mb-4">
              <h2 class="card-title text-base">
                {gettext("Photos (%{count})", count: length(@installation.picture_keys))}
              </h2>
            </div>

            <.installation_photos_grid
              id="photos-grid"
              pictures={@installation.picture_keys}
              editable={true}
              empty_title={gettext("No photos yet")}
              empty_message={gettext("Upload your first photo to showcase this installation.")}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_000_000 -> "#{Float.round(bytes / 1_000_000, 1)} MB"
      bytes >= 1_000 -> "#{trunc(bytes / 1_000)} KB"
      true -> "#{bytes} B"
    end
  end
end
