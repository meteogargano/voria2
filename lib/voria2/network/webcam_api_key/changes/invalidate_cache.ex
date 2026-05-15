defmodule Voria2.Network.WebcamApiKey.Changes.InvalidateCache do
  use Ash.Resource.Change

  def change(changeset, _, _) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      Voria2.Cache.invalidate_webcam_key(record.key)
      {:ok, record}
    end)
  end
end
