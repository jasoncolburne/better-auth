using Workerd = import "/workerd/workerd.capnp";

const config :Workerd.Config = (
  services = [
    (name = "main", worker = .cloudflareWorker),
  ],
  sockets = [ ( name = "main", address = "*:8080", http = (), service = "main" ) ]
);

const cloudflareWorker :Workerd.Worker = (
  modules = [
    (name = "server", esModule = embed "dist/entry.js"),
  ],
  compatibilityDate = "2024-01-01"
);
