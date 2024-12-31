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

  @connected_cids :__connected_cids__
  @connected_process_dict :__connected_process_dict__
  @connected_tag :__connected_tag__
  @connected_mounted :__connected_mounted__
  @connected_attach :__connected_attach__
  @connected_detach :__connected_detach__
  @connected_detach_event "phx:connected_detach"

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
       attach_hook(
         socket,
         :connected_handle_info,
         :handle_info,
         &ConnectedComponent.connected_handle_info/2
       )}
    end
  end

  ## Public

  @doc """
  Sends a message to a ConnectedComponent via its `@myself` assign. Useful for
  child-to-parent communication.
  """
  def send_component(cid, message) do
    if component_pid = Process.get({@connected_process_dict, cid}) do
      send(component_pid, message)
    else
      Logger.warning("no pid found for target component id #{inspect(cid)}")
      message
    end
  end

  ## Internal

  @doc """
  Handler function for handle_info hook in ConnectedComponent.LiveView.
  """
  def connected_handle_info({@connected_attach, cid, {module, id}}, socket) do
    {:halt, put_connected_cid(socket, cid, {module, id})}
  end

  def connected_handle_info({@connected_detach, cid}, socket) do
    {:halt, delete_connected_cid(socket, cid)}
  end

  def connected_handle_info({@connected_tag, cid, message}, socket) do
    case get_connected_cid(socket, cid) do
      {module, id} ->
        send_update(module, %{@connected_tag => :handle_info, :id => id, :message => message})
        {:halt, socket}

      _otherwise ->
        {:halt, socket}
    end
  end

  def connected_handle_info(_info, socket), do: {:cont, socket}

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
          Phoenix.LiveView.JS.push(@connected_detach_event, target: socket.assigns.myself)

        socket
        |> assign(assigns)
        |> assign(@connected_mounted, true)
        |> assign(:connected_attrs, %{"phx-remove": connected_remove})
        |> attach_hook(:connected_handle_detach, :handle_event, fn
          @connected_detach_event, _params, socket -> {:halt, detach_component_process(socket)}
          _event, _params, socket -> {:cont, socket}
        end)
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
          attach_component_process(socket, component_module, process_setup)
      end

    component_module.handle_update(assigns, socket)
  end

  @doc """
  Init function for process spawned by a ConnectedComponent.
  """
  def component_process(parent_pid, cid, process_setup) do
    process_setup.()
    component_process_lifecycle(parent_pid, cid)
  end

  ## Private

  defp get_connected_cid(socket, cid) do
    Map.get(socket.private[@connected_cids] || %{}, cid)
  end

  defp put_connected_cid(socket, cid, module_and_id) do
    private = socket.private[@connected_cids] || %{}
    private = Map.put(private, cid, module_and_id)
    Phoenix.LiveView.put_private(socket, @connected_cids, private)
  end

  defp delete_connected_cid(socket, cid) do
    private = socket.private[@connected_cids] || %{}
    private = Map.delete(private, cid)
    Phoenix.LiveView.put_private(socket, @connected_cids, private)
  end

  defp attach_component_process(socket, component_module, process_setup) do
    cid = socket.assigns.myself

    send(self(), {@connected_attach, cid, {component_module, socket.assigns.id}})

    spawn_args = [self(), cid, process_setup]
    pid = spawn_link(__MODULE__, :component_process, spawn_args)

    Process.put({@connected_process_dict, cid}, pid)

    socket
  end

  defp detach_component_process(socket) do
    cid = socket.assigns.myself

    send(self(), {@connected_detach, cid})

    if component_pid = Process.get({@connected_process_dict, cid}) do
      send(component_pid, :unmount)
      Process.delete({@connected_process_dict, cid})
    end

    socket
  end

  defp component_process_lifecycle(parent_pid, cid) do
    receive do
      :unmount ->
        nil

      message ->
        send(parent_pid, {@connected_tag, cid, message})
        component_process_lifecycle(parent_pid, cid)
    end
  end
end
