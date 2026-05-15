defmodule Voria2Web.InstallationComponents do
  @moduledoc """
  Reusable components for installation-related features.
  """
  use Phoenix.Component
  use Gettext, backend: Voria2Web.Gettext

  import Voria2Web.CoreComponents
  alias Phoenix.LiveView.JS

  @doc """
  Renders a grid of installation pictures.

  ## Options

    * `:pictures` - List of picture keys (required)
    * `:editable` - Whether to show delete buttons (default: false)
    * `:empty_title` - Empty state title (default: "No photos yet")
    * `:empty_message` - Empty state message (default: nil)
  """
  attr :id, :string, required: true
  attr :pictures, :list, required: true, doc: "List of picture keys"
  attr :editable, :boolean, default: false, doc: "Show delete buttons"
  attr :empty_title, :string, default: nil
  attr :empty_message, :string, default: nil

  def installation_photos_grid(assigns) do
    ~H"""
    <div :if={@pictures == []} class="text-center py-12 text-base-content/40">
      <div class="size-12  bg-base-200 flex items-center justify-center mx-auto mb-4 ring-1 ring-base-300">
        <.icon name="hero-photo" class="size-6 text-base-content/30" />
      </div>
      <h3 class="text-base font-semibold text-base-content">
        {@empty_title || gettext("No photos yet")}
      </h3>
      <p :if={@empty_message} class="text-sm text-base-content/50 mt-1">
        {@empty_message}
      </p>
    </div>

    <div
      :if={@pictures != []}
      id={@id}
      phx-hook=".PhotoLightbox"
      class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4"
    >
      <div
        :for={{picture_key, idx} <- Enum.with_index(@pictures)}
        class="group relative aspect-video bg-base-200 rounded-lg overflow-hidden"
      >
        <img
          src={Voria2.Storage.public_url(Voria2.InstallationIngest.thumbnail_key(picture_key))}
          alt={gettext("Installation photo")}
          loading="lazy"
          class="w-full h-full object-cover cursor-pointer transition-transform duration-300 group-hover:scale-105"
          data-full-url={Voria2.Storage.public_url(picture_key)}
          data-index={idx}
        />
        <div
          :if={@editable}
          class="absolute inset-0 bg-black/0 group-hover:bg-black/20 transition-colors duration-200"
        >
          <button
            class="absolute top-2 right-2 btn btn-circle btn-sm btn-error opacity-0 group-hover:opacity-100 transition-opacity duration-200"
            phx-click={JS.push("delete_photo", value: %{picture_key: picture_key})}
            title={gettext("Delete photo")}
          >
            <.icon name="hero-trash" class="size-3.5" />
          </button>
        </div>
      </div>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".PhotoLightbox">
      export default {
        mounted() {
          this.el.addEventListener('click', this.handleClick.bind(this))
          document.addEventListener('keydown', this.handleKeyDown.bind(this))
          this.overlay = null
          this.currentIndex = 0
          this.urls = []
        },

        destroyed() {
          document.removeEventListener('keydown', this.handleKeyDown)
          if (this.overlay) {
            this.closeLightbox()
          }
        },

        handleClick(e) {
          const img = e.target.closest('img[data-full-url]')
          if (img) {
            this.urls = Array.from(this.el.querySelectorAll('img[data-full-url]')).map(i => i.dataset.fullUrl)
            this.currentIndex = parseInt(img.dataset.index)
            this.openLightbox()
          }
        },

        openLightbox() {
          if (this.overlay) {
            this.closeLightbox()
            return
          }

          this.overlay = document.createElement('div')
          this.overlay.className = 'fixed inset-0 z-50 bg-black/90 backdrop-blur-sm flex items-center justify-center cursor-zoom-out animate-fade-in'
          this.overlay.dataset.lightbox = 'true'

          this.currentImage = document.createElement('img')
          this.currentImage.src = this.urls[this.currentIndex]
          this.currentImage.className = 'max-w-[90vw] max-h-[90vh] object-contain'
          this.currentImage.loading = 'lazy'

          const prevBtn = this.createNavButton('←', () => {
            this.currentIndex = (this.currentIndex - 1 + this.urls.length) % this.urls.length
            this.currentImage.src = this.urls[this.currentIndex]
          })

          const nextBtn = this.createNavButton('→', () => {
            this.currentIndex = (this.currentIndex + 1) % this.urls.length
            this.currentImage.src = this.urls[this.currentIndex]
          })

          this.overlay.appendChild(prevBtn)
          this.overlay.appendChild(this.currentImage)
          this.overlay.appendChild(nextBtn)

          this.overlay.addEventListener('click', (e) => {
            if (e.target === this.overlay) {
              this.closeLightbox()
            }
          })

          document.body.appendChild(this.overlay)
        },

        createNavButton(text, onClick) {
          const btn = document.createElement('button')
          btn.textContent = text
          btn.className = 'absolute top-1/2 -translate-y-1/2 btn btn-circle btn-lg bg-black/50 hover:bg-black/70 border-0 text-white'
          btn.style.left = text === '←' ? '1rem' : 'auto'
          btn.style.right = text === '→' ? '1rem' : 'auto'
          btn.addEventListener('click', (e) => {
            e.stopPropagation()
            onClick()
          })
          return btn
        },

        closeLightbox() {
          if (this.overlay) {
            this.overlay.remove()
            this.overlay = null
          }
        },

        handleKeyDown(e) {
          if (!this.overlay) return

          if (e.key === 'Escape') {
            this.closeLightbox()
          } else if (e.key === 'ArrowLeft') {
            e.preventDefault()
            this.overlay.querySelector('button:first-child')?.click()
          } else if (e.key === 'ArrowRight') {
            e.preventDefault()
            this.overlay.querySelector('button:last-child')?.click()
          }
        }
      }
    </script>
    """
  end
end
