defmodule Voria2.Accounts do
  use Ash.Domain, otp_app: :voria2

  resources do
    resource Voria2.Accounts.Token

    resource Voria2.Accounts.User do
      define :get_by_email, action: :get_by_email, get_by: [:email]
      define :register_with_password, action: :register_with_password
      define :destroy_user, action: :destroy
    end
  end
end
