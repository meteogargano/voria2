defmodule Voria2Web.ManageLive.Installations.Form do
  use Voria2Web, :live_view

  on_mount {Voria2Web.LiveUserAuth, :live_user_required}

  def mount(params, _session, socket) do
    socket = assign(socket, :active_section, :installations)

    socket =
      case socket.assigns.live_action do
        :new ->
          form =
            AshPhoenix.Form.for_create(
              Voria2.Network.Installation,
              :create,
              actor: socket.assigns.current_user
            )
            |> to_form()

          socket
          |> assign(:page_title, gettext("New Installation"))
          |> assign(:form, form)
          |> assign(:installation, nil)

        :edit ->
          id = params["id"]

          case Voria2.Network.get_installation(id, actor: socket.assigns.current_user) do
            {:ok, installation} ->
              form =
                AshPhoenix.Form.for_update(
                  installation,
                  :update,
                  actor: socket.assigns.current_user
                )
                |> to_form()

              socket
              |> assign(:page_title, gettext("Edit %{name}", name: installation.name))
              |> assign(:form, form)
              |> assign(:installation, installation)

            {:error, _} ->
              socket
              |> put_flash(:error, gettext("Installation not found."))
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
        Map.put(params, "user_id", socket.assigns.current_user.id)
      else
        params
      end

    case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
      {:ok, installation} ->
        message =
          if socket.assigns.live_action == :new,
            do: gettext("Installation created."),
            else: gettext("Installation updated.")

        {:noreply,
         socket
         |> put_flash(:info, message)
         |> push_navigate(to: ~p"/manage/installations/#{installation.id}")}

      {:error, form} ->
        {:noreply, assign(socket, :form, form |> to_form())}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl">
      <.breadcrumb crumbs={[
        {gettext("Installations"), ~p"/manage/installations"},
        {if(@live_action == :new, do: gettext("New"), else: @installation.name), nil}
      ]} />

      <.header>
        {@page_title}
        <:subtitle :if={@live_action == :new}>
          {gettext("Add a new physical location to your network.")}
        </:subtitle>
      </.header>

      <div class="mt-4">
        <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-0">
          <div class=" border border-base-300 bg-base-100 divide-y divide-base-300 overflow-hidden">
            <div class="px-6 py-4 bg-base-200/40">
              <h3 class="text-sm font-semibold">{gettext("Basic Information")}</h3>
            </div>
            <div class="px-6 py-5 space-y-4">
              <.input
                field={@form[:name]}
                type="text"
                label={gettext("Name")}
                placeholder={gettext("My Weather Station")}
              />
              <.input
                field={@form[:description]}
                type="textarea"
                label={gettext("Description")}
                placeholder={gettext("Optional notes about this installation")}
                rows="3"
              />
              <.input field={@form[:is_active]} type="checkbox" label={gettext("Active")} />
            </div>

            <div class="px-6 py-4 bg-base-200/40">
              <h3 class="text-sm font-semibold">{gettext("Location")}</h3>
            </div>
            <div class="px-6 py-5 space-y-4">
              <div class="grid grid-cols-2 gap-4">
                <.input
                  field={@form[:city]}
                  type="text"
                  label={gettext("City")}
                  placeholder={gettext("Rome")}
                />
                <.input
                  field={@form[:country]}
                  type="text"
                  label={gettext("Country")}
                  placeholder={gettext("Italy")}
                />
              </div>
              <.input
                field={@form[:timezone]}
                type="text"
                label={gettext("Timezone")}
                placeholder="Europe/Rome"
              />
              <div class="grid grid-cols-3 gap-4">
                <.input
                  field={@form[:latitude]}
                  type="number"
                  label={gettext("Latitude")}
                  placeholder="41.9028"
                  step="any"
                />
                <.input
                  field={@form[:longitude]}
                  type="number"
                  label={gettext("Longitude")}
                  placeholder="12.4964"
                  step="any"
                />
                <.input
                  field={@form[:altitude]}
                  type="number"
                  label={gettext("Altitude (m)")}
                  placeholder="21"
                  step="any"
                />
              </div>
            </div>
          </div>

          <div class="flex justify-end gap-3 mt-4">
            <.link navigate={~p"/manage/installations"} class="btn btn-ghost btn-sm">
              {gettext("Cancel")}
            </.link>
            <.button type="submit" variant="primary">
              {if @live_action == :new,
                do: gettext("Create Installation"),
                else: gettext("Save Changes")}
            </.button>
          </div>
        </.form>
      </div>
    </div>
    """
  end
end
