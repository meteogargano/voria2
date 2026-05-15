defmodule Voria2.Storage do
  @type object_info :: %{
          key: String.t(),
          size: non_neg_integer() | nil,
          last_modified: String.t() | nil,
          etag: String.t() | nil,
          content_type: String.t() | nil
        }

  @callback upload(binary(), String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  @callback delete(String.t(), String.t()) :: :ok | {:error, term()}
  @callback list(String.t(), String.t()) :: {:ok, [object_info()]} | {:error, term()}
  @callback download(String.t(), String.t()) ::
              {:ok,
               %{body: binary(), content_type: String.t() | nil, size: non_neg_integer() | nil}}
              | {:error, term()}

  def adapter, do: Application.get_env(:voria2, :storage_adapter, Voria2.Storage.R2)
  def upload(binary, key, bucket), do: adapter().upload(binary, key, bucket)
  def delete(key, bucket), do: adapter().delete(key, bucket)
  def list(prefix, bucket), do: adapter().list(prefix, bucket)
  def download(key, bucket), do: adapter().download(key, bucket)

  def public_url(key) do
    case Application.get_env(:voria2, :storage_public_endpoint) do
      nil -> nil
      base -> "#{base}/#{key}"
    end
  end
end
