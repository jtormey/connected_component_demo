defmodule AppWeb.ConnectedLive.NestedComponent do
  use AppWeb, :connected_component

  def render(assigns) do
    ~H"""
    <div {@connected_attrs} class="border border-zinc-200 p-8 rounded-xl">
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

  def on_mount(socket) do
    process_setup = fn ->
      Phoenix.PubSub.subscribe(App.PubSub, "nested_updates")
    end

    {:ok, socket, process_setup}
  end

  def handle_update(assigns, socket) do
    {:ok, assign(socket, :parent, assigns.parent)}
  end

  def handle_event("inc", _params, socket) do
    {:noreply, update(socket, :count, &(&1 + 1))}
  end

  def handle_event("inc_send", _params, socket) do
    send_component(socket.assigns.myself, :inc)
    {:noreply, socket}
  end

  def handle_event("inc_parent", _params, socket) do
    send_component(socket.assigns.parent, :inc)
    {:noreply, socket}
  end

  def handle_info(:inc, socket) do
    {:noreply, update(socket, :count, &(&1 + 1))}
  end
end
