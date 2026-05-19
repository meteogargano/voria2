defmodule Voria2.BlogContent do
  @moduledoc false

  @prefix "blogcontent/"

  def prefix, do: @prefix

  def bucket do
    Application.get_env(:voria2, :storage_bucket, "voria2-media")
  end

  def list_files do
    with {:ok, objects} <- Voria2.Storage.list(@prefix, bucket()) do
      {:ok,
       objects
       |> Enum.filter(&top_level_file?/1)
       |> Enum.sort_by(&String.downcase(filename(&1.key)))}
    end
  end

  def upload(filename, binary, opts \\ []) when is_binary(filename) and is_binary(binary) do
    with {:ok, safe_name} <- normalize_filename(filename),
         {:ok, upload_name, upload_binary} <- maybe_convert_to_webp(safe_name, binary, opts),
         {:ok, target_name} <- unique_filename(upload_name),
         {:ok, key} <- Voria2.Storage.upload(upload_binary, object_key(target_name), bucket()) do
      {:ok, key}
    end
  end

  def delete(key) when is_binary(key) do
    with {:ok, validated_key} <- validate_key(key),
         :ok <- Voria2.Storage.delete(validated_key, bucket()) do
      :ok
    end
  end

  def download(key) when is_binary(key) do
    with {:ok, validated_key} <- validate_key(key) do
      Voria2.Storage.download(validated_key, bucket())
    end
  end

  def filename(key) when is_binary(key) do
    key
    |> String.trim_leading(@prefix)
    |> Path.basename()
  end

  def object_key(filename) when is_binary(filename), do: @prefix <> filename

  defp top_level_file?(%{key: key}) do
    String.starts_with?(key, @prefix) and
      key != @prefix and
      not String.contains?(String.trim_leading(key, @prefix), "/")
  end

  defp validate_key(key) do
    cond do
      not String.starts_with?(key, @prefix) -> {:error, :invalid_key}
      key == @prefix -> {:error, :invalid_key}
      String.contains?(String.trim_leading(key, @prefix), "/") -> {:error, :invalid_key}
      true -> {:ok, key}
    end
  end

  defp normalize_filename(filename) do
    trimmed = filename |> String.trim() |> Path.basename()

    cond do
      trimmed in ["", ".", ".."] ->
        {:error, :invalid_filename}

      String.contains?(trimmed, ["/", "\\"]) ->
        {:error, :invalid_filename}

      true ->
        {:ok, trimmed}
    end
  end

  defp unique_filename(filename) do
    with {:ok, files} <- list_files() do
      existing_names = MapSet.new(Enum.map(files, &__MODULE__.filename(&1.key)))
      {:ok, pick_available_filename(filename, existing_names)}
    end
  end

  defp pick_available_filename(filename, existing_names) do
    if MapSet.member?(existing_names, filename) do
      ext = Path.extname(filename)
      base = Path.rootname(filename, ext)

      Stream.iterate(2, &(&1 + 1))
      |> Stream.map(fn index -> "#{base}-#{index}#{ext}" end)
      |> Enum.find(&(not MapSet.member?(existing_names, &1)))
    else
      filename
    end
  end

  defp maybe_convert_to_webp(filename, binary, opts) do
    if Keyword.get(opts, :convert_to_webp, false) do
      with {:ok, image} <- Image.from_binary(binary),
           {:ok, webp_binary} <- Image.write(image, :memory, suffix: ".webp") do
        {:ok, webp_filename(filename), webp_binary}
      end
    else
      {:ok, filename, binary}
    end
  end

  defp webp_filename(filename) do
    ext = Path.extname(filename)
    base = Path.rootname(filename, ext)
    base <> ".webp"
  end
end
