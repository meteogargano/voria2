defmodule Voria2Web.ManageLive.BlogContent.Index do
  use Voria2Web, :live_view

  on_mount {Voria2Web.LiveUserAuth, :live_user_required}

  @max_upload_size 25_000_000

  @impl true
  def mount(_params, _session, socket) do
    unless socket.assigns.current_user.admin do
      {:ok,
       socket
       |> put_flash(:error, gettext("Admin access required."))
       |> push_navigate(to: ~p"/manage")}
    else
      socket =
        socket
        |> assign(:page_title, gettext("Blog Content"))
        |> assign(:active_section, :blogcontent)
        |> assign(:convert_images_to_webp, false)
        |> assign(:files, list_files())
        |> assign(:selected_file, nil)
        |> allow_upload(:files,
          accept: :any,
          max_file_size: @max_upload_size,
          max_entries: 10,
          auto_upload: true,
          progress: &handle_progress/3
        )

      {:ok, socket}
    end
  end

  @impl true
  def handle_event("validate", params, socket) do
    {:noreply,
     assign(socket, :convert_images_to_webp, truthy_param?(params["convert_images_to_webp"]))}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :files, ref)}
  end

  def handle_event("preview", %{"key" => key}, socket) do
    {:noreply, assign(socket, :selected_file, find_file(socket.assigns.files, key))}
  end

  def handle_event("clear_preview", _params, socket) do
    {:noreply, assign(socket, :selected_file, nil)}
  end

  def handle_event("delete_file", %{"id" => key}, socket) do
    case Voria2.BlogContent.delete(key) do
      :ok ->
        files = list_files()

        {:noreply,
         socket
         |> assign(:files, files)
         |> maybe_clear_selected_file(key)
         |> put_flash(:info, gettext("File deleted."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to delete file."))}
    end
  end

  def handle_progress(:files, entry, socket) do
    if entry.done? do
      result =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          with {:ok, binary} <- File.read(path),
               {:ok, key} <-
                 Voria2.BlogContent.upload(entry.client_name, binary,
                   convert_to_webp: socket.assigns.convert_images_to_webp and image_upload?(entry)
                 ) do
            {:ok, key}
          else
            {:error, reason} -> {:error, reason}
          end
        end)

      case result do
        key when is_binary(key) ->
          files = list_files()

          {:noreply,
           socket
           |> assign(:files, files)
           |> assign(:selected_file, find_file(files, key))
           |> put_flash(:info, gettext("File uploaded successfully."))}

        {:error, :invalid_filename} ->
          {:noreply, put_flash(socket, :error, gettext("Invalid filename."))}

        {:error, reason} ->
          {:noreply,
           put_flash(
             socket,
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
    <div class="space-y-6">
      <.breadcrumb crumbs={[{gettext("Blog Content"), nil}]} />

      <.header>
        {gettext("Blog Content")}
        <:subtitle>
          {gettext(
            "Upload, preview, copy public links, download, and delete files stored in the blogcontent folder."
          )}
        </:subtitle>
      </.header>

      <div class="grid gap-6 xl:grid-cols-[minmax(0,1.75fr)_minmax(20rem,1fr)]">
        <div class="space-y-6">
          <div class="card bg-base-200 border border-base-300">
            <div class="card-body p-6">
              <h2 class="card-title text-base">{gettext("Upload Files")}</h2>

              <form phx-change="validate" id="blogcontent-upload-form">
                <div
                  id="blogcontent-dropzone"
                  class={[
                    "border-2 border-dashed p-8 text-center transition-colors relative",
                    if(@uploads.files.entries == [],
                      do: "border-base-300 hover:border-primary",
                      else: "border-primary bg-primary/5"
                    )
                  ]}
                  phx-drop-target={@uploads.files.ref}
                >
                  <div class="space-y-3 pointer-events-none relative z-10">
                    <div class="size-12 rounded-full bg-primary/10 flex items-center justify-center mx-auto">
                      <.icon name="hero-cloud-arrow-up" class="size-6 text-primary" />
                    </div>
                    <div>
                      <p class="font-semibold text-base-content">
                        {gettext("Drop files here or click to browse")}
                      </p>
                      <p class="text-sm text-base-content/60 mt-1">
                        {gettext("Any file type up to 25MB. Duplicate filenames are auto-renamed.")}
                      </p>
                    </div>
                    <button type="button" class="btn btn-primary btn-sm pointer-events-none">
                      {gettext("Choose Files")}
                    </button>
                  </div>

                  <.live_file_input upload={@uploads.files} class="absolute inset-0 opacity-0 z-20" />
                </div>

                <div class="mt-4 rounded-xl border border-base-300 bg-base-100/60 px-4 py-3">
                  <.input
                    id="blogcontent-convert-images-to-webp"
                    name="convert_images_to_webp"
                    type="checkbox"
                    checked={@convert_images_to_webp}
                    label={gettext("Convert image uploads to WebP")}
                  />
                  <p class="text-sm text-base-content/60">
                    {gettext("When enabled, uploaded images are converted and stored as .webp files.")}
                  </p>
                </div>
              </form>

              <div :if={@uploads.files.entries != []} class="mt-4 space-y-2">
                <h3 class="text-sm font-semibold text-base-content/70">{gettext("Uploading...")}</h3>
                <%= for entry <- @uploads.files.entries do %>
                  <div class="flex items-center gap-3 p-2 rounded-lg bg-base-300/30">
                    <div class="flex-1 min-w-0">
                      <p class="text-sm font-medium truncate">{entry.client_name}</p>
                      <p class="text-xs text-base-content/60">{format_bytes(entry.client_size)}</p>
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

          <div class="card bg-base-200 border border-base-300">
            <div class="card-body p-0 overflow-x-auto">
              <div class="flex items-center justify-between px-6 py-5 border-b border-base-300">
                <h2 class="card-title text-base">
                  {gettext("Files (%{count})", count: length(@files))}
                </h2>
              </div>

              <table id="blogcontent-files" class="table table-zebra">
                <thead>
                  <tr>
                    <th>{gettext("Name")}</th>
                    <th>{gettext("Type")}</th>
                    <th>{gettext("Size")}</th>
                    <th>{gettext("Updated")}</th>
                    <th class="w-32 text-right">{gettext("Actions")}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :if={@files == []} id="blogcontent-empty-state">
                    <td colspan="5" class="py-10 text-center text-base-content/50">
                      {gettext("No files yet.")}
                    </td>
                  </tr>
                  <tr :for={file <- @files} id={row_id(file)}>
                    <td class="font-medium">{Voria2.BlogContent.filename(file.key)}</td>
                    <td>{file_label(file)}</td>
                    <td>{format_bytes(file.size || 0)}</td>
                    <td>{format_timestamp(file.last_modified)}</td>
                    <td class="w-32">
                      <div class="flex items-center justify-end gap-1">
                        <button
                          id={"preview-file-#{dom_id(file.key)}"}
                          type="button"
                          class="btn btn-ghost btn-xs btn-square"
                          phx-click="preview"
                          phx-value-key={file.key}
                          title={gettext("View")}
                          aria-label={gettext("View")}
                        >
                          <.icon name="hero-eye" class="size-3.5" />
                        </button>
                        <button
                          id={"copy-file-link-#{dom_id(file.key)}"}
                          type="button"
                          class="btn btn-ghost btn-xs btn-square"
                          data-key-target={"file-public-link-#{dom_id(file.key)}"}
                          data-copied-text={gettext("Copied!")}
                          onclick="var el=document.getElementById(this.dataset.keyTarget);var text=el.textContent.trim();var done=()=>{this.title=this.dataset.copiedText;this.setAttribute('aria-label',this.dataset.copiedText);this.classList.add('text-success');setTimeout(()=>{this.title=this.dataset.defaultTitle;this.setAttribute('aria-label',this.dataset.defaultTitle);this.classList.remove('text-success')},2000)};if(navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(text).then(done)}else{var textarea=document.createElement('textarea');textarea.value=text;textarea.setAttribute('readonly','');textarea.style.position='absolute';textarea.style.left='-9999px';document.body.appendChild(textarea);textarea.select();document.execCommand('copy');document.body.removeChild(textarea);done()}"
                          data-default-title={gettext("Copy link")}
                          title={gettext("Copy link")}
                          aria-label={gettext("Copy link")}
                        >
                          <.icon name="hero-document-duplicate" class="size-3.5" />
                        </button>
                        <code id={"file-public-link-#{dom_id(file.key)}"} class="hidden">
                          {public_url(file.key)}
                        </code>
                        <button
                          id={"delete-file-button-#{dom_id(file.key)}"}
                          type="button"
                          class="btn btn-ghost btn-xs btn-square text-error hover:bg-error/10"
                          onclick={"document.getElementById('delete-file-#{dom_id(file.key)}').showModal()"}
                          title={gettext("Delete")}
                          aria-label={gettext("Delete")}
                        >
                          <.icon name="hero-trash" class="size-3.5" />
                        </button>
                        <.confirm_modal
                          id={"delete-file-#{dom_id(file.key)}"}
                          title={
                            gettext("Delete %{name}?", name: Voria2.BlogContent.filename(file.key))
                          }
                          message={gettext("This removes the file from R2 immediately.")}
                          confirm_label={gettext("Delete")}
                          confirm_event="delete_file"
                          confirm_value={%{id: file.key}}
                          danger={true}
                        />
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>

        <div class="card bg-base-200 border border-base-300 h-fit">
          <div class="card-body p-6">
            <div class="flex items-center justify-between gap-3">
              <h2 class="card-title text-base">{gettext("Preview")}</h2>
              <button
                :if={@selected_file}
                type="button"
                class="btn btn-ghost btn-xs btn-square"
                phx-click="clear_preview"
                title={gettext("Clear")}
                aria-label={gettext("Clear")}
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>

            <%= if @selected_file do %>
              <div id="blogcontent-preview" class="space-y-4">
                <div>
                  <div class="font-semibold break-all">
                    {Voria2.BlogContent.filename(@selected_file.key)}
                  </div>
                  <div class="text-sm text-base-content/60 mt-1">
                    {file_label(@selected_file)}
                    {" • "}
                    {format_bytes(@selected_file.size || 0)}
                  </div>
                </div>

                <div class="rounded-xl border border-base-300 bg-base-100 overflow-hidden min-h-48">
                  <%= case preview_kind(@selected_file) do %>
                    <% :image -> %>
                      <img
                        id="blogcontent-preview-image"
                        src={asset_url(@selected_file.key)}
                        alt={Voria2.BlogContent.filename(@selected_file.key)}
                        class="w-full h-auto"
                      />
                    <% :pdf -> %>
                      <div class="p-6 text-sm text-base-content/70 space-y-3">
                        <p>
                          {gettext("PDF preview is not available here. Download the file to view it.")}
                        </p>
                        <.link
                          href={download_url(@selected_file.key)}
                          class="btn btn-primary btn-sm"
                        >
                          <.icon name="hero-arrow-down-tray" class="size-4" />
                          {gettext("Download PDF")}
                        </.link>
                      </div>
                    <% :audio -> %>
                      <div class="p-6">
                        <audio id="blogcontent-preview-audio" controls class="w-full">
                          <source
                            src={asset_url(@selected_file.key)}
                            type={content_type(@selected_file)}
                          />
                        </audio>
                      </div>
                    <% :video -> %>
                      <video
                        id="blogcontent-preview-video"
                        controls
                        class="w-full h-auto max-h-[32rem] bg-black"
                      >
                        <source
                          src={asset_url(@selected_file.key)}
                          type={content_type(@selected_file)}
                        />
                      </video>
                    <% :text -> %>
                      <iframe
                        id="blogcontent-preview-iframe"
                        src={asset_url(@selected_file.key)}
                        class="w-full h-[32rem]"
                      >
                      </iframe>
                    <% :other -> %>
                      <div class="p-6 text-sm text-base-content/70 space-y-3">
                        <p>{gettext("Inline preview is not available for this file type.")}</p>
                        <.link
                          href={download_url(@selected_file.key)}
                          class="btn btn-primary btn-sm"
                        >
                          <.icon name="hero-arrow-down-tray" class="size-4" />
                          {gettext("Download File")}
                        </.link>
                      </div>
                  <% end %>
                </div>

                <div class="flex gap-2">
                  <.link
                    href={asset_url(@selected_file.key)}
                    class="btn btn-ghost btn-sm"
                    target="_blank"
                  >
                    <.icon name="hero-arrow-top-right-on-square" class="size-4" />
                    {gettext("Open")}
                  </.link>
                  <.link href={download_url(@selected_file.key)} class="btn btn-primary btn-sm">
                    <.icon name="hero-arrow-down-tray" class="size-4" />
                    {gettext("Download")}
                  </.link>
                </div>
              </div>
            <% else %>
              <div id="blogcontent-preview-empty" class="text-sm text-base-content/50 py-10">
                {gettext("Select a file from the table to preview it here.")}
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp list_files do
    case Voria2.BlogContent.list_files() do
      {:ok, files} -> files
      {:error, _reason} -> []
    end
  end

  defp find_file(files, key), do: Enum.find(files, &(&1.key == key))

  defp maybe_clear_selected_file(socket, key) do
    if socket.assigns.selected_file && socket.assigns.selected_file.key == key do
      assign(socket, :selected_file, nil)
    else
      socket
    end
  end

  defp preview_url(key, download?) do
    path = Voria2.BlogContent.filename(key)

    if download? do
      ~p"/manage/blogcontent/files/#{path}?download=1"
    else
      ~p"/manage/blogcontent/files/#{path}"
    end
  end

  defp public_url(key), do: Voria2.Storage.public_url(key)

  defp asset_url(key), do: public_url(key) || preview_url(key, false)

  defp download_url(key), do: public_url(key) || preview_url(key, true)

  defp row_id(file), do: "blogcontent-file-#{dom_id(file.key)}"

  defp dom_id(key) do
    key
    |> String.replace(~r/[^a-zA-Z0-9]+/, "-")
    |> String.trim("-")
    |> String.downcase()
  end

  defp file_label(file) do
    content_type(file) || MIME.from_path(file.key)
  end

  defp content_type(file), do: file[:content_type]

  defp preview_kind(file) do
    type = content_type(file) || MIME.from_path(file.key)

    cond do
      String.starts_with?(type, "image/") -> :image
      String.starts_with?(type, "audio/") -> :audio
      String.starts_with?(type, "video/") -> :video
      String.starts_with?(type, "text/") -> :text
      type == "application/pdf" -> :pdf
      true -> :other
    end
  end

  defp format_timestamp(nil), do: "-"

  defp format_timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        gettext("%{timestamp} UTC", timestamp: Calendar.strftime(datetime, "%Y-%m-%d %H:%M"))

      _ ->
        value
    end
  end

  defp format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_000_000 -> gettext("%{size} MB", size: Float.round(bytes / 1_000_000, 1))
      bytes >= 1_000 -> gettext("%{size} KB", size: trunc(bytes / 1_000))
      true -> gettext("%{size} B", size: bytes)
    end
  end

  defp image_upload?(entry) do
    String.starts_with?(entry.client_type || "", "image/") or
      image_filename?(entry.client_name)
  end

  defp image_filename?(filename) do
    case filename |> Path.extname() |> String.downcase() do
      ".jpg" -> true
      ".jpeg" -> true
      ".png" -> true
      ".gif" -> true
      ".webp" -> true
      _ -> false
    end
  end

  defp truthy_param?(value), do: value in [true, "true", "1", "on"]
end
