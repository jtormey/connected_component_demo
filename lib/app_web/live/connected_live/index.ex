defmodule AppWeb.ConnectedLive.Index do
  use AppWeb, :live_view

  alias AppWeb.ConnectedLive

  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-8">
        <.button phx-click="inc_a_pubsub">Increment A (PubSub)</.button>
        <.button phx-click="inc_b_pubsub">Increment B (PubSub)</.button>
        <.button phx-click="inc_nested_pubsub">Increment Nested (PubSub)</.button>
      </div>
      <.tab_group>
        <:tab active={@tab == "a"} patch={~p"/a"}>Tab Component A</:tab>
        <:tab active={@tab == "b"} patch={~p"/b"}>Tab Component B</:tab>
      </.tab_group>
      <div class="py-8">
        <.live_component :if={@tab == "a"} module={ConnectedLive.TabComponent} id="tab_a" count={0} />
        <.live_component :if={@tab == "b"} module={ConnectedLive.TabComponent} id="tab_b" count={0} />
      </div>
    </div>
    """
  end

  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :tab, params["tab"] || "a")}
  end

  def handle_event("inc_a_pubsub", _params, socket) do
    Phoenix.PubSub.broadcast(App.PubSub, "tab_a_updates", :inc)
    {:noreply, socket}
  end

  def handle_event("inc_b_pubsub", _params, socket) do
    Phoenix.PubSub.broadcast(App.PubSub, "tab_b_updates", :inc)
    {:noreply, socket}
  end

  def handle_event("inc_nested_pubsub", _params, socket) do
    Phoenix.PubSub.broadcast(App.PubSub, "nested_updates", :inc)
    {:noreply, socket}
  end
end
