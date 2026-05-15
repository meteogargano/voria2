defmodule Voria2Web.PreferencesHTML do
  use Voria2Web, :html
  use Gettext, backend: Voria2Web.Gettext

  embed_templates "preferences_html/*"
end
