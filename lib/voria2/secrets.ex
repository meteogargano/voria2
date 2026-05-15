defmodule Voria2.Secrets do
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        Voria2.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:voria2, :token_signing_secret)
  end
end
