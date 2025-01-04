# Connected Component Demo

Allows LiveComponents to receive messages from other processes, for example by subscribing to PubSub topics.

Find the demo source code in [AppWeb.ConnectedLive.Index](./lib/app_web/live/connected_live/index.ex).

https://github.com/user-attachments/assets/4a1790c0-fb85-45ba-a869-229b54f71bda

## How it Works

To create a ConnectedComponent, use it in a module:

    use ConnectedComponent

The following optional callbacks are available:

    * `on_mount(socket)` - Called once on the first `update/2` of the component lifecycle.
    * `handle_update(assigns, socket)` - Called on each call to `update/2`.
    * `handle_info(info, socket)` - Called when the parent LiveView relays a message targeted at the component.

All initial assigns are automatically assigned to the socket before `on_mount/1` is called.

The `on_mount/1` callback should return `{:ok, socket, fun}`, where `fun` is used to set up PubSub
subscriptions, or any other method of receiving messages from other processes.

Messages received by the component process are relayed back to the ConnectedComponent via its parent
LiveView, using `send_update/3` internally. The process exits when the component detaches.

For proper unmounting, be sure to add the required attrs to the top level element of the component:

    <div {@connected_attrs}>
      <% # Component implementation... %>
    </div>

Child-to-parent communication is also possible, using `send_component/2` and `@myself`. See the
function documentation for details.

## Run the Demo App

To start your Phoenix server:

  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.
