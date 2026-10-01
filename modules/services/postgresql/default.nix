{
  config,
  pkgs,
  ...
}:

{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;

    # Allow local TCP connections
    enableTCPIP = true;

    settings = {
      max_connections = 50;
      shared_buffers = "256MB";
      work_mem = "8MB";
      fsync = true;
      synchronous_commit = true;
    };
  };
}
