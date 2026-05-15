defmodule Voria2Web.ManageLive.Users.Profile do
  use Voria2Web, :live_view

  on_mount {Voria2Web.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    form =
      AshPhoenix.Form.for_update(
        socket.assigns.current_user,
        :change_password,
        actor: socket.assigns.current_user
      )
      |> to_form()

    {:ok,
     socket
     |> assign(:page_title, gettext("Profile"))
     |> assign(:active_section, :profile)
     |> assign(:form, form)}
  end

  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form.source, params) |> to_form()
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
      {:ok, _user} ->
        form =
          AshPhoenix.Form.for_update(
            socket.assigns.current_user,
            :change_password,
            actor: socket.assigns.current_user
          )
          |> to_form()

        {:noreply,
         socket
         |> put_flash(:info, gettext("Password updated successfully."))
         |> assign(:form, form)}

      {:error, form} ->
        {:noreply, assign(socket, :form, form |> to_form())}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl">
      <.breadcrumb crumbs={[{gettext("Profile"), nil}]} />

      <.header>
        {gettext("Profile")}
        <:subtitle>{gettext("Manage your account and security settings.")}</:subtitle>
      </.header>

      <div class="mt-4 space-y-6">
        <.detail_section title={gettext("Account Information")}>
          <:item label={gettext("Name")}>{@current_user.name || "—"}</:item>
          <:item label={gettext("Email")}>{@current_user.email}</:item>
          <:item label={gettext("Role")}>
            <span class={[
              "badge badge-sm",
              @current_user.admin && "badge-warning",
              !@current_user.admin && "badge-ghost"
            ]}>
              {if @current_user.admin, do: gettext("Admin"), else: gettext("User")}
            </span>
          </:item>
          <:item label={gettext("Confirmed")}>
            {if @current_user.confirmed_at,
              do: Calendar.strftime(@current_user.confirmed_at, "%b %d, %Y"),
              else: gettext("Pending")}
          </:item>
        </.detail_section>

        <div class=" border border-base-300 bg-base-100 divide-y divide-base-300 overflow-hidden">
          <div class="px-6 py-4 bg-base-200/40">
            <h3 class="text-sm font-semibold">{gettext("Change Password")}</h3>
          </div>
          <div class="px-6 py-5">
            <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-4">
              <.input
                field={@form[:current_password]}
                type="password"
                label={gettext("Current Password")}
                autocomplete="current-password"
              />
              <.input
                field={@form[:password]}
                type="password"
                label={gettext("New Password")}
                autocomplete="new-password"
              />
              <.input
                field={@form[:password_confirmation]}
                type="password"
                label={gettext("Confirm New Password")}
                autocomplete="new-password"
              />
              <div class="flex justify-end pt-2">
                <.button type="submit" variant="primary">
                  {gettext("Update Password")}
                </.button>
              </div>
            </.form>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
