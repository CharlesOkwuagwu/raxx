defmodule ServerSentEvents.Router do
  alias Raxx.Response
  alias Raxx.ServerSentEvents, as: SSE

  def handle_request(%{path: [], method: :GET}, _opts) do
    Response.ok(home_page)
  end

  def handle_request(%{path: ["events"], method: :GET}, env) do
    Process.send_after(self, 0, 1000)
    SSE.upgrade(__MODULE__, env, %{initial: "hello"})
  end

  def handle_request(_request, _opts) do
    Response.not_found("Page not found")
  end

  # handle_info
  def handle_info(10, _opts) do
    {:send, ""}
  end
  def handle_info(i, _opts) when rem(i, 2) == 0 do
    Process.send_after(self, i + 1, 1000)
    chunk = SSE.Event.new("#{i}", event: "count") |> SSE.Event.to_chunk
    {:send, chunk}
  end
  def handle_info(i, _opts) do
    Process.send_after(self, i + 1, 1000)
    :nosend
  end

  # terminate

  defp home_page do
    """
<!DOCTYPE html>
<html>
	<head>
		<script type="text/javascript">
			function ready() {
				if (!!window.EventSource) {
					setupEventSource();
				} else {
					document.getElementById('status').innerHTML =
						"Sorry but your browser doesn't support the EventSource API";
				}
			}
			function setupEventSource() {
				var source = new EventSource('/events');
        source.onmessage = function(e){
          console.log(e)
        }
				source.addEventListener('count', function(event) {
					addStatus("server sent the following: '" + event.data + "'");
					}, false);
					source.addEventListener('open', function(event) {
            console.log(event)
						addStatus('eventsource connected.')
					}, false);
					source.addEventListener('error', function(event) {
						if (event.eventPhase == EventSource.CLOSED) {
							addStatus('eventsource was closed.')
						}
					}, false);
			}
			function addStatus(text) {
				var date = new Date();
				document.getElementById('status').innerHTML
				= document.getElementById('status').innerHTML
				+ date + ": " + text + "<br/>";
			}
		</script>
	</head>
	<body onload="ready();">
		Hi!
		<div id="status"></div>
	</body>
</html>
    """
  end
end
