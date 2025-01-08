defmodule AppWeb.DisconnectedLive.Index do
  use AppWeb, :live_view

  alias AppWeb.DisconnectedLive

  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-8">
        <.button phx-click="inc_a_pubsub">Increment A (PubSub)</.button>
        <.button phx-click="inc_b_pubsub">Increment B (PubSub)</.button>
        <.button phx-click="inc_nested_pubsub">Increment Nested (PubSub)</.button>
      </div>
      <.tab_group>
        <:tab active={@tab == "a"} patch={~p"/disconnected/a"}>Tab Component A</:tab>
        <:tab active={@tab == "b"} patch={~p"/disconnected/b"}>Tab Component B</:tab>
      </.tab_group>
      <div class="py-8">
        <.live_component
          :if={@tab == "a"}
          module={DisconnectedLive.TabComponent}
          id="tab_a"
          count={0}
        />
        <.live_component
          :if={@tab == "b"}
          module={DisconnectedLive.TabComponent}
          id="tab_b"
          count={0}
        />
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(App.PubSub, "nested_updates")
    end

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    tab = params["tab"] || "a"

    if connected?(socket) do
      case tab do
        "a" ->
          Phoenix.PubSub.unsubscribe(App.PubSub, "tab_b_updates")
          Phoenix.PubSub.subscribe(App.PubSub, "tab_a_updates")

        "b" ->
          Phoenix.PubSub.unsubscribe(App.PubSub, "tab_a_updates")
          Phoenix.PubSub.subscribe(App.PubSub, "tab_b_updates")
      end
    end

    {:noreply, assign(socket, :tab, tab)}
  end

  def handle_info(:inc_a, socket) do
    send_update(self(), DisconnectedLive.TabComponent, id: "tab_a", message: :inc)
    {:noreply, socket}
  end

  def handle_info(:inc_b, socket) do
    send_update(self(), DisconnectedLive.TabComponent, id: "tab_b", message: :inc)
    {:noreply, socket}
  end

  def handle_info(:inc_nested, socket) do
    send_update(self(), DisconnectedLive.NestedComponent, id: "nested", message: :inc)
    {:noreply, socket}
  end

  # NOTE: Have to change message names to be distinct, as otherwise
  #   we wouldn't know which component to route the message to.

  def handle_event("inc_a_pubsub", _params, socket) do
    Phoenix.PubSub.broadcast(App.PubSub, "tab_a_updates", :inc_a)
    {:noreply, socket}
  end

  def handle_event("inc_b_pubsub", _params, socket) do
    Phoenix.PubSub.broadcast(App.PubSub, "tab_b_updates", :inc_b)
    {:noreply, socket}
  end

  def handle_event("inc_nested_pubsub", _params, socket) do
    Phoenix.PubSub.broadcast(App.PubSub, "nested_updates", :inc_nested)
    {:noreply, socket}
  end
end
