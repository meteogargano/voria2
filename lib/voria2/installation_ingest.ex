defmodule Voria2.InstallationIngest do
  @max_file_size 10 * 1024 * 1024

  def process(installation, binary, actor) do
    if byte_size(binary) > @max_file_size do
      {:error, :file_too_large}
    else
      hash = Base.encode16(:crypto.hash(:sha256, binary), case: :lower)
      full_key = "installations/#{installation.id}/#{hash}.webp"

      if full_key in (installation.picture_keys || []) do
        {:duplicate, full_key}
      else
        with {:ok, img} <- Image.from_binary(binary),
             {:ok, webp_binary} <- Image.write(img, :memory, suffix: ".webp"),
             bucket = Application.get_env(:voria2, :storage_bucket, "voria2-media"),
             {:ok, _} <- Voria2.Storage.upload(webp_binary, full_key, bucket),
             {:ok, thumb_img} <- Image.thumbnail(img, 300),
             {:ok, thumb_binary} <- Image.write(thumb_img, :memory, suffix: ".webp"),
             thumb_key = String.replace(full_key, ".webp", "_thumb.webp"),
             {:ok, _} <- Voria2.Storage.upload(thumb_binary, thumb_key, bucket) do
          updated = Voria2.Network.add_installation_picture(installation, full_key, actor: actor)
          {:ok, updated}
        else
          {:error, reason} -> {:error, reason}
        end
      end
    end
  end

  def thumbnail_key(picture_key) do
    String.replace(picture_key, ".webp", "_thumb.webp")
  end
end
