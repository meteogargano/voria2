defmodule Voria2Web.AuthOverrides do
  use AshAuthentication.Phoenix.Overrides
  alias AshAuthentication.Phoenix.Components
  alias Voria2Web.AuthSignInForm

  # configure your UI overrides here

  # First argument to `override` is the component name you are overriding.
  # The body contains any number of configurations you wish to override
  # Below are some examples

  # For a complete reference, see https://hexdocs.pm/ash_authentication_phoenix/ui-overrides.html

  override Components.Banner do
    set :root_class, "hidden"
    set :image_url, "/images/app-logo.svg"
    set :dark_image_url, "/images/app-logo.svg"
    set :href_url, "/"
    set :text, nil
  end

  override Components.Password do
    set :register_toggle_text, nil
    set :reset_toggle_text, nil
    set :sign_in_extra_component, nil
    set :sign_in_form_module, AuthSignInForm
  end
end
