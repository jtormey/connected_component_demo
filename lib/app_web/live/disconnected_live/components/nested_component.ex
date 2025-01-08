defmodule AppWeb.DisconnectedLive.NestedComponent do
  use AppWeb, :live_component

  def render(assigns) do
    ~H"""
    <div class="border border-zinc-200 p-8 rounded-xl">
      <div class="mb-4">
        This is {@id}. Count: {@count}
      </div>
      <div class="flex flex-wrap gap-2">
        <.button phx-click="inc" phx-target={@myself}>Increment (handle_event)</.button>
        <.button phx-click="inc_send" phx-target={@myself}>Increment (send_component)</.button>
        <.button phx-click="inc_parent" phx-target={@myself}>
          Increment Parent (send_component)
        </.button>
      </div>
    </div>
    """
  end

  def update(%{message: :inc}, socket) do
    {:ok, update(socket, :count, &(&1 + 1))}
  end

  def update(assigns, socket) do
    if socket.assigns[:mounted?] do
      {:ok, assign(socket, :parent, assigns[:parent])}
    else
      {:ok, assign(assign(socket, assigns), :mounted?, true)}
    end
  end

  def handle_event("inc", _params, socket) do
    {:noreply, update(socket, :count, &(&1 + 1))}
  end

  def handle_event("inc_send", _params, socket) do
    send_update(self(), socket.assigns.myself, message: :inc)
    {:noreply, socket}
  end

  def handle_event("inc_parent", _params, socket) do
    send_update(self(), socket.assigns.parent, message: :inc)
    {:noreply, socket}
  end
end
