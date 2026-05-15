defmodule Voria2Web.ManageLive.Webcams.Form do
  use Voria2Web, :live_view

  on_mount {Voria2Web.LiveUserAuth, :live_user_required}

  def mount(params, _session, socket) do
    socket = assign(socket, :active_section, :installations)

    socket =
      case socket.assigns.live_action do
        :new ->
          installation_id = params["installation_id"]

          case Voria2.Network.get_installation(installation_id,
                 actor: socket.assigns.current_user
               ) do
            {:ok, installation} ->
              form =
                AshPhoenix.Form.for_create(
                  Voria2.Network.Webcam,
                  :create,
                  actor: socket.assigns.current_user
                )
                |> to_form()

              socket
              |> assign(:page_title, "New Webcam")
              |> assign(:form, form)
              |> assign(:installation, installation)
              |> assign(:webcam, nil)

            {:error, _} ->
              socket
              |> put_flash(:error, gettext("Installation not found."))
              |> push_navigate(to: ~p"/manage/installations")
          end

        :edit ->
          id = params["id"]

          case Voria2.Network.get_webcam(id, actor: socket.assigns.current_user) do
            {:ok, webcam} ->
              form =
                AshPhoenix.Form.for_update(
                  webcam,
                  :update,
                  actor: socket.assigns.current_user
                )
                |> to_form()

              installation =
                case webcam.installation_id do
                  nil ->
                    nil

                  iid ->
                    case Voria2.Network.get_installation(iid,
                           actor: socket.assigns.current_user
                         ) do
                      {:ok, i} -> i
                      _ -> nil
                    end
                end

              socket
              |> assign(:page_title, gettext("Edit %{name}", name: webcam.name))
              |> assign(:form, form)
              |> assign(:installation, installation)
              |> assign(:webcam, webcam)

            {:error, _} ->
              socket
              |> put_flash(:error, gettext("Webcam not found."))
              |> push_navigate(to: ~p"/manage/installations")
          end
      end

    {:ok, socket}
  end

  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form.source, params) |> to_form()
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"form" => params}, socket) do
    params =
      if socket.assigns.live_action == :new do
        Map.put(params, "installation_id", socket.assigns.installation.id)
      else
        params
      end

    case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
      {:ok, webcam} ->
        message =
          if socket.assigns.live_action == :new,
            do: gettext("Webcam created."),
            else: gettext("Webcam updated.")

        {:noreply,
         socket
         |> put_flash(:info, message)
         |> push_navigate(to: ~p"/manage/webcams/#{webcam.id}")}

      {:error, form} ->
        {:noreply, assign(socket, :form, form |> to_form())}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl">
      <.breadcrumb crumbs={[
        {gettext("Installations"), ~p"/manage/installations"},
        {if(@installation, do: @installation.name, else: "…"),
         if(@installation, do: ~p"/manage/installations/#{@installation.id}", else: nil)},
        {if(@live_action == :new, do: gettext("New Webcam"), else: @webcam.name), nil}
      ]} />

      <.header>
        {@page_title}
        <:subtitle :if={@live_action == :new && @installation}>
          {gettext("Adding a webcam to %{name}.", name: @installation.name)}
        </:subtitle>
      </.header>

      <div class="mt-4">
        <.form for={@form} phx-change="validate" phx-submit="save">
          <div class=" border border-base-300 bg-base-100 divide-y divide-base-300 overflow-hidden">
            <div class="px-6 py-4 bg-base-200/40">
              <h3 class="text-sm font-semibold">{gettext("Webcam Details")}</h3>
            </div>
            <div class="px-6 py-5 space-y-4">
              <.input
                field={@form[:name]}
                type="text"
                label={gettext("Name")}
                placeholder={gettext("Rooftop Cam")}
              />
              <.input
                field={@form[:slug]}
                type="text"
                label={gettext("Slug")}
                placeholder="rooftop-cam"
              />
              <.input
                field={@form[:description]}
                type="textarea"
                label={gettext("Description")}
                placeholder={gettext("Optional description")}
                rows="3"
              />
              <.input
                field={@form[:stream_url]}
                type="url"
                label={gettext("Stream URL")}
                placeholder="rtsp://..."
              />
              <.input field={@form[:is_active]} type="checkbox" label={gettext("Active")} />
            </div>
          </div>

          <div class="flex justify-end gap-3 mt-4">
            <.link
              navigate={
                if @installation,
                  do: ~p"/manage/installations/#{@installation.id}",
                  else: ~p"/manage/installations"
              }
              class="btn btn-ghost btn-sm"
            >
              {gettext("Cancel")}
            </.link>
            <.button type="submit" variant="primary">
              {if @live_action == :new,
                do: gettext("Create Webcam"),
                else: gettext("Save Changes")}
            </.button>
          </div>
        </.form>
      </div>
    </div>
    """
  end
end
