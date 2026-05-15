defmodule Voria2.Accounts.Validations.RegistrationEnabled do
  use Ash.Resource.Validation

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(_changeset, _opts, context) do
    cond do
      Application.get_env(:voria2, :registration_enabled, false) -> :ok
      context.actor && Map.get(context.actor, :admin) -> :ok
      true -> {:error, field: :base, message: "Registration is currently disabled"}
    end
  end
end
