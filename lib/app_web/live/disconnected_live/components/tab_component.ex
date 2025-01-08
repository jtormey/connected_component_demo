defmodule AppWeb.DisconnectedLive.TabComponent do
  use AppWeb, :live_component

  alias AppWeb.DisconnectedLive

  def render(assigns) do
    ~H"""
    <div class="border border-zinc-200 p-8 rounded-xl">
      <div class="mb-4">
        This is {@id}. Count: {@count}
      </div>
      <.button phx-click="inc" phx-target={@myself}>Increment (handle_event)</.button>
      <.button phx-click="inc_send" phx-target={@myself}>Increment (send_component)</.button>
      <div class="mt-8">
        <.live_component
          module={DisconnectedLive.NestedComponent}
          id="nested"
          parent={@myself}
          count={0}
        />
      </div>
    </div>
    """
  end

  def update(%{message: :inc}, socket) do
    {:ok, update(socket, :count, &(&1 + 1))}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  def handle_event("inc", _params, socket) do
    {:noreply, update(socket, :count, &(&1 + 1))}
  end

  def handle_event("inc_send", _params, socket) do
    send_update(self(), socket.assigns.myself, message: :inc)
    {:noreply, socket}
  end
end
