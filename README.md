# Raxx: an Elixir webserver interface

Raxx is:

- The specification of a **pure** interface for webservers and frameworks.
- A simple and powerful tools library for building refined web applications


To use Raxx provide an app: A module that implements `handle_request/2`, taking a request and config as arguments and return a respone map

- `status`:  The HTTP response code
- `headers`: A collection of headers
- `body`: An binary or io_list


```elixir
defmodule MyApp do
  def handle_request(_request, _config) do
    %{status: 200, headers: [{"content-type", "text/html"}], body: "A barebones raxx app."}
  end
end

Ace.HTTP.start_link({MyApp, :no_config}, port: 8080)
```

[Documentation for Raxx is available online](https://hexdocs.pm/raxx)

[Introductory presentation of Raxx](https://www.youtube.com/watch?v=80AXtvXFIA4&index=2&list=PLWbHc_FXPo2ivlIjzcaHS9N_Swe_0hWj0)

## Supported Web servers

- [ace](https://github.com/CrowdHailer/raxx/tree/master/ace_http)
- [cowboy](https://github.com/CrowdHailer/raxx/tree/master/raxx_cowboy)
- [elli](https://github.com/CrowdHailer/raxx/tree/master/raxx_elli)

## Hello, World!

A (slightly) less simplistic example utilitising `Raxx.Response` for convenience.

```elixir
defmodule HelloWeb.Server do
  import Raxx.Response

  def handle_request(%{path: []}, _env) do
    ok("Hello, World!")
  end

  def handle_request(%{path: [name]}, _env) do
    ok("Hello, #{name}!")
  end

  def handle_request(%{path: _unknown}, _env) do
    not_found()
  end
end
```

Mount your server in you application. *Example using [Ace](https://github.com/CrowdHailer/Ace)*

```elixir
defmodule HelloWeb do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      worker(Ace.HTTP, [{HelloWeb.Server, []}, [port: 8080]])
    ]

    opts = [strategy: :one_for_one]
    Supervisor.start_link(children, opts)
  end
end
```

### Principles

- Stateless HTTP request fulfill a valuable role in modern applications and will continue to do so, this simple usecase must not be compicated by catering to more advanced communication patterns.
- Use Ruby rack and Clojure ring as inspiration, but be happy to break away from historic CGI-style header names.
- Surface utilities so that it can be used in general HTTP based applications, a RFC6265 module could be used by plug and rack
- Be a good otp citizen, work well in an umbrella app,
- Raxx is designed to be the foundation of a VC (view controller) framework. Other applications in the umbrella should act as the model.
- [Your server as a function](https://monkey.org/~marius/funsrv.pdf)
- No support for working with errors, throws, exits. We handle them in debugging because elixir is a dynamic language but they should not be used for routing or responses other than 500.

*Raxx is inspired by the [Ruby's Rack interface](http://rack.github.io/) and [Clojure's Ring interface](https://github.com/ring-clojure).*

## Raxx applications

A Raxx application module has a `handle_request/2` function that takes a `Raxx.Request` and an application environment, as arguments.
For every incomming HTTP connnection `handle_request/2` is called.

The application may indicate to the server that it should respond with a simple HTTP response buy returning a `Raxx.Response` struct.

```elixir
defmodule MySimpleApp do
  def handle_request(_r, _env), do: Raxx.Response.ok()
end
```

Alternativly the the application may indicate that the connection should be upgraded.
In the case of an upgrade the returned upgrade object specifies the communication protocol required.

```elixir
defmodule MyChunkingApp do
  def handle_request(_r, env), do: Raxx.Chunked.upgrade({__MODULE__, env})
  def handle_info(message, _env), do: {:send, "ping"}
end
```

Currently the following upgraded protocols are supported, with others (such as websockets), in development.

- HTTP Chunked
- Server Sent Events

### Raxx.Request

`Raxx.Request`

HTTP requests to a Raxx application are encapsulated in a `Raxx.Request` struct.

```elixir
%Raxx.Request{
  host: "www.example.com",
  path: ["some", "path"],
  ...
}
```

Data can easily be read from the request directly and through pattern matching.
This allows for expressive routing in raxx apps without a routing DSL.
The hello world example is a great example of this.

The `Raxx.Request` module provides additional functionality for inspect the request.
For example inspecting cookies.

```elixir
defmodule Router do
  import Raxx.Request

  def handle_request(request = %{path: ["api" | rest]}, env) do
    ApiRouter.handle_request(%{request | path: rest}, env)
  end

  def handle_request(request = %{path: ["users"], method: method}, _env) do
    case method do
      :GET ->
        query = request.query
        # Get all the users that match a query
      "POST" ->
        data = request.body
        # Create a user with the following data
      "PATCH" ->
        user_id = parse_cookies(request)["user-id"]
        # Update a the details of the user from a cookie session
    end
  end
end
```

To see the details of each request object checkout the [cowboy example](https://github.com/CrowdHailer/raxx/tree/master/example/cowboy_example).

### Raxx.Response

`Raxx.Response`

Any map with the required keys (`:status`, `:headers`, `:body`) can be interpreted by the server as a simple HTTP response.
However it is more usual to return a `Raxx.Response` struct which has sensible defaults for all fields.

Manually creating response structs can be tedious.
The `Raxx.Response` module has several helpers for creating response maps.
This include setting status codes, manipulating cookies

```elixir
defmodule FooRouter do
  alias Raxx.Response
  def handle_request(%{path: ["users"], method: :GET}, _env) do
    Response.ok("All users: Andy, Bethany, Clive")
  end

  def handle_request(%{path: ["users"], method: "POST", body: data}, _env) do
    case MyApp.create_user(data) do
      {:ok, user} -> Response.created("New user #{user}")
      {:error, :already_exists} -> Response.conflict("sorry")
      {:error, :bad_params} -> Response.bad_request("sorry")
      {:error, :database_fail} -> Response.bad_gateway("sorry")
      {:error, _unknown} -> Response.internal_server_error("Well that's weird")
    end
  end

  def handle_request(%{path: ["users"], method: _}, _env) do
    Response.method_not_allowed("Don't do that")
  end

  def handle_request(%{path: ["users", id], method: :GET}, _env) do
    case MyApp.get_user(id) do
      {:ok, user} -> Response.ok("New user #{user}")
      {:error, nil} -> Response.not_found("User unknown")
      {:error, :deleted} -> Response.gone("User deleted")
    end
  end

  def handle_request(_request, _env) do
    Response.not_found("Sorry didn't get that")
  end
end
```

### Raxx.Chunked

`Raxx.Chunked` allows data to be streamed to the client.
An unbounded amount of response data may be sent this way.

A Raxx application that returns a `Raxx.Chunked` struct from a call to `handle_request/2`, is indicating that it wishes to send the response in chunks.

```elixir
%Raxx.Chunked{
  app: {MyHandler, :none},
  ...
}
```

A chunked handler must implement a `handle_info/2` callback.
This callback is called everytime the request process recieves a message, taking the message and environment as arguments.

```elixir
defmodule Ping do
  def handler_request(_, _), do: Raxx.Chunked.upgrade({__MODULE__, nil})

  def handle_info({:data, chunk}), do: {:send, chunk}
  def handle_info({_), do: :nosend
end
```

## Contributing

If you have Elixir installed on your machine then you can treat this project as a normal mix project and run tests via `mix test`.

If required a development environment can be created using [Vagrant](www.vagrantup.com).

## Discussions

These are not issues because there is not a decision on how best to proceed.

#### Host header

All information in the host header is duplicated in other parts the request struct.
The Host header is always required.

Therefore should the host header be deleted from this list of headers?
It should never be relied on and users building request might add a host field but not a host header

#### Virtual host

Can the `Host` header have a path in the URL?

Raxx.Request.host + Raxx.Request.mount = virtual host

Router.host instead of Router.mount

#### Debug page

Eventually I think that all Raxx Applications should be pure.
This means that the only error that occurs is when the server process also fails.
Therefor the only reason for a debugger is to handle the imperfect compiler,
i.e. unrecognised runtime errors.
This is a useful case at the moment.
Defining the raxx application as pure means error handling belongs in the server that is hosting the Raxx application.
It may want to send error information through supervision and not catching errors because of this.

> Note that calls inside try/1 are not tail recursive since the VM
> needs to keep the stacktrace in case an exception happens.

https://github.com/elixir-lang/elixir/blob/22bd10a8170af0b187029d115abe4cc8edcf2ae6/lib/elixir/lib/kernel/special_forms.ex#L1622

To see a raxx implementation of errors and debug pages check out version [0.9.0]()

#### Lost information from paths

Raxx will turn a variety of different path strings to the same path

```
"//" == "/" -> []
"/a//b" = "/a/b" -> ["a", "b"]
"/a/?" == "/a/" == "/a" -> ["a"]
```

I want Raxx to loose as little information about the request as possible.
Therefore should the Server implemetations redirect clients to the canonical url

#### HTTP connection model

Call `handle_request` before the body is recieved.
allows body to be streamed.
test with websockets.
All so check uses for transfer encoding in requests.

#### Streamed Requests

Large requests raise a number of issues and the current case of reading the whole request before calling the application.
- If the request can be determined to be invalid from the headers then don't need to read the request.
- files might be too large.

There are a variety of solutions.
- call application once headers read.
  handle_request -> response | {:stream, state} | {:read, state}
- write upload to file as read.
  This will be at the adapter level.
  Could be configured to go straight to IPFS/S3, I assume that S3 has a rename API call.
  Use a worker to clean up the remote files, both sanitise and delete old

#### Extensible map of state machines

Raxx.Waiting / Raxx.ReadingStartLine -> Raxx.ReadingHeaders -> Raxx.ReadingBody -> Raxx.Waiting
Raxx.Waiting -> Raxx.ReadingMultipart -> Raxx.SendingChunks

upgrade is just a way to replace whole state machine in Ace server. probably alot like socket hijack.

Every state should have a `to_send` property.

*Pachyderm*
Entire Causality protocol over HTTP. Custom state machine, handle_conflict etc
Send a backlog of requests as a multipart/pacyderm; version=1
