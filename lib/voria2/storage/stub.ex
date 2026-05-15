defmodule Voria2.Storage.Stub do
  @behaviour Voria2.Storage

  @table :voria2_storage_stub

  @impl true
  def list(prefix, bucket) do
    {:ok,
     @table
     |> ensure_table()
     |> :ets.tab2list()
     |> Enum.filter(fn {{stored_bucket, key}, _object} ->
       stored_bucket == bucket and String.starts_with?(key, prefix)
     end)
     |> Enum.map(fn {{_bucket, key}, object} ->
       %{
         key: key,
         size: byte_size(object.body),
         last_modified: object.last_modified,
         etag: nil,
         content_type: object.content_type
       }
     end)}
  end

  @impl true
  def upload(binary, key, bucket) do
    table = ensure_table(@table)

    object = %{
      body: binary,
      content_type: MIME.from_path(key),
      last_modified: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }

    true = :ets.insert(table, {{bucket, key}, object})
    {:ok, key}
  end

  @impl true
  def delete(key, bucket) do
    table = ensure_table(@table)
    true = :ets.delete(table, {bucket, key})
    :ok
  end

  @impl true
  def download(key, bucket) do
    table = ensure_table(@table)

    case :ets.lookup(table, {bucket, key}) do
      [{{^bucket, ^key}, object}] ->
        {:ok,
         %{
           body: object.body,
           content_type: object.content_type,
           size: byte_size(object.body)
         }}

      [] ->
        {:error, :not_found}
    end
  end

  def put_object(key, body, opts \\ []) do
    bucket = Keyword.get(opts, :bucket, default_bucket())
    content_type = Keyword.get(opts, :content_type, MIME.from_path(key))
    last_modified = Keyword.get(opts, :last_modified, DateTime.utc_now() |> DateTime.to_iso8601())
    table = ensure_table(@table)

    true =
      :ets.insert(
        table,
        {{bucket, key}, %{body: body, content_type: content_type, last_modified: last_modified}}
      )

    :ok
  end

  def reset! do
    table = ensure_table(@table)
    :ets.delete_all_objects(table)
    :ok
  end

  defp default_bucket do
    Application.get_env(:voria2, :storage_bucket, "voria2-media")
  end

  defp ensure_table(table) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, [:named_table, :public, :set])
      tid -> tid
    end
  end
end
