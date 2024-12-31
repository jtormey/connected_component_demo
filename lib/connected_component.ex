defmodule ConnectedComponent do
  @moduledoc """
  Connects a LiveComponent with a parent LiveView, allowing it to seamlessly receive
  messages via `handle_info/2`, as if it were a normal LiveView.

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
  """

  import Phoenix.Component
  import Phoenix.LiveView

  require Logger

  @type socket() :: Phoenix.LiveView.Socket.t()

  @callback on_mount(socket :: socket()) :: {:ok, socket()} | {:ok, socket(), function()}
  @callback handle_update(map(), socket :: socket()) :: {:ok, socket()}
  @callback handle_info(term(), socket :: socket()) :: {:noreply, socket()}

  @connected_process_dict :__connected_process_dict__
  @connected_tag :__connected_tag__
  @connected_mounted :__connected_mounted__
  @connected_attach :__connected_attach__
  @connected_detach_event "__connected_detach__"

  defmacro __using__(_opts) do
    quote do
      @behaviour unquote(__MODULE__)

      use Phoenix.LiveComponent

      import unquote(__MODULE__), only: [send_component: 2]

      @impl Phoenix.LiveComponent
      def update(assigns, socket) do
        unquote(__MODULE__).update(__MODULE__, assigns, socket)
      end

      @impl unquote(__MODULE__)
      def on_mount(socket) do
        {:ok, socket}
      end

      @impl unquote(__MODULE__)
      def handle_update(_assigns, socket) do
        {:ok, socket}
      end

      @impl unquote(__MODULE__)
      def handle_info(_message, socket) do
        {:noreply, socket}
      end

      defoverridable on_mount: 1, handle_update: 2, handle_info: 2
    end
  end

  defmodule LiveView do
    @moduledoc """
    Configures a LiveView for use with ConnectedComponents.
    """
    defmacro __using__(_opts) do
      quote do
        on_mount unquote(__MODULE__)
      end
    end

    def on_mount(:default, _params, _session, socket) do
      {:cont,
       socket
       |> attach_hook(:attach_connected, :handle_info, &ConnectedComponent.attach_connected/2)
       |> attach_hook(:detach_connected, :handle_event, &ConnectedComponent.detach_connected/3)}
    end
  end

  ## Public

  @doc """
  Explicitly attaches a ConnectedComponent to the LiveView socket.
  """
  def attach_component(socket, module, opts) do
    id = opts[:id] || raise("opt :id is required when calling attach_component/3")

    handle_info = fn {@connected_tag, {^module, ^id}, message}, socket ->
      send_update(module, %{@connected_tag => :handle_info, :id => id, :message => message})
      {:halt, socket}
    end

    attach_hook(socket, "#{module}.#{id}", :handle_info, handle_info)
  end

  @doc """
  Explicitly detaches a ConnectedComponent from the LiveView socket.
  """
  def detach_component(socket, module, opts) do
    id = opts[:id] || raise("opt :id is required when calling detach_component/3")

    details = {module, id}
    send(_component_pid = Process.get({@connected_process_dict, details}), :unmount)

    detach_hook(socket, "#{module}.#{id}", :handle_info)
  end

  @doc """
  Sends a message to a ConnectedComponent via its `@myself` assign. Useful for
  child-to-parent communication.
  """
  def send_component(target, message) do
    if details = Process.get({@connected_process_dict, target}) do
      send(_component_pid = Process.get({@connected_process_dict, details}), message)
    else
      Logger.warning("no pid found for target #{inspect(target)}")
      message
    end
  end

  ## Internal

  @doc """
  Handler function for handle_info hook in ConnectedComponent.LiveView.
  """
  def attach_connected({@connected_attach, {module, id}}, socket) do
    {:halt, attach_component(socket, module, id: id)}
  end

  def attach_connected(_info, socket), do: {:cont, socket}

  @doc """
  Handler function for handle_event hook in ConnectedComponent.LiveView.
  """
  def detach_connected(@connected_detach_event, %{"myself" => target}, socket) do
    cid = %Phoenix.LiveComponent.CID{cid: String.to_integer(target)}

    case Process.get({@connected_process_dict, cid}) do
      {module, id} -> {:halt, detach_component(socket, module, id: id)}
      _otherwise -> {:halt, socket}
    end
  end

  def detach_connected(_event, _params, socket), do: {:cont, socket}

  @doc """
  Callback implementation for LiveComponent `update/2`.
  """
  def update(component_module, %{@connected_tag => :handle_info} = assigns, socket) do
    case component_module.handle_info(assigns.message, socket) do
      {:noreply, socket} ->
        {:ok, socket}

      value ->
        raise "handle_info/2 must return `{:noreply, socket}`, received: #{inspect(value)}"
    end
  end

  def update(component_module, assigns, socket) do
    mount_result =
      if socket.assigns[@connected_mounted] do
        :mounted
      else
        connected_remove =
          Phoenix.LiveView.JS.push(
            @connected_detach_event,
            value: %{myself: to_string(socket.assigns.myself)}
          )

        socket
        |> assign(assigns)
        |> assign(@connected_mounted, true)
        |> assign(:connected_attrs, %{"phx-remove": connected_remove})
        |> component_module.on_mount()
      end

    socket =
      case mount_result do
        :mounted ->
          socket

        {:ok, socket} ->
          Logger.warning(
            "process_setup function not provided, consider using a normal LiveComponent"
          )

          socket

        {:ok, socket, process_setup} when is_function(process_setup, 0) ->
          details = {component_module, socket.assigns.id}

          spawn_args = [self(), details, process_setup]
          pid = spawn_link(__MODULE__, :component_process, spawn_args)

          Process.put({@connected_process_dict, details}, pid)
          Process.put({@connected_process_dict, socket.assigns.myself}, details)

          send(self(), {@connected_attach, details})

          socket
      end

    component_module.handle_update(assigns, socket)
  end

  @doc """
  Init function for process spawned by a ConnectedComponent.
  """
  def component_process(parent_pid, details, process_setup) do
    process_setup.()
    component_process_lifecycle(parent_pid, details)
  end

  ## Private

  defp component_process_lifecycle(parent_pid, details) do
    receive do
      :unmount ->
        nil

      message ->
        send(parent_pid, {@connected_tag, details, message})
        component_process_lifecycle(parent_pid, details)
    end
  end
end
