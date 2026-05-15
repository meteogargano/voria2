defmodule Voria2Web.AuthSignInBranding do
  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <div class="mb-8 text-center">
      <a href="/" class="inline-flex flex-col items-center gap-4">
        <div class="size-20">
          <img
            src="/images/app-logo.svg"
            alt="MeteoGargano logo"
            class="block size-full object-contain"
          />
        </div>
        <div class="space-y-1">
          <p class="text-[11px] font-semibold uppercase tracking-[0.32em] text-base-content/45">
            MeteoGargano
          </p>
          <h1 class="text-2xl font-semibold tracking-tight text-base-content">
            Network Management
          </h1>
        </div>
      </a>
    </div>
    """
  end
end
