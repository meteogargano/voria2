defmodule Voria2Web.AuthSignInForm do
  use AshAuthentication.Phoenix.Web, :live_component

  alias AshAuthentication.Phoenix.Components.Password.SignInForm

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  def render(assigns) do
    ~H"""
    <div>
      <Voria2Web.AuthSignInBranding.render />

      <.live_component
        module={SignInForm}
        id={@id <> "-base"}
        strategy={@strategy}
        label={@label}
        auth_routes_prefix={@auth_routes_prefix}
        overrides={@overrides}
        current_tenant={@current_tenant}
        context={@context}
        gettext_fn={@gettext_fn}
      />
    </div>
    """
  end
end
