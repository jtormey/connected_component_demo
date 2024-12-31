defmodule AppWeb.ConnectedLive.TabComponent do
  use AppWeb, :connected_component

  alias AppWeb.ConnectedLive

  def render(assigns) do
    ~H"""
    <div {@connected_attrs} class="border border-zinc-200 p-8 rounded-xl">
      <div class="mb-4">
        This is {@id}. Count: {@count}
      </div>
      <.button phx-click="inc" phx-target={@myself}>Increment (handle_event)</.button>
      <.button phx-click="inc_send" phx-target={@myself}>Increment (send_component)</.button>
      <div class="mt-8">
        <.live_component
          module={ConnectedLive.NestedComponent}
          id="nested"
          parent={@myself}
          count={0}
        />
      </div>
    </div>
    """
  end

  def on_mount(socket) do
    id = socket.assigns.id

    process_setup = fn ->
      Phoenix.PubSub.subscribe(App.PubSub, "#{id}_updates")
    end

    {:ok, socket, process_setup}
  end

  def handle_event("inc", _params, socket) do
    {:noreply, update(socket, :count, &(&1 + 1))}
  end

  def handle_event("inc_send", _params, socket) do
    send_component(socket.assigns.myself, :inc)
    {:noreply, socket}
  end

  def handle_info(:inc, socket) do
    {:noreply, update(socket, :count, &(&1 + 1))}
  end
end
