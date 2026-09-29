{
  config,
  pkgs,
  lib,
  ...
}:

{
  # PostgreSQL
  services.postgresql = {
    enable = true;

    # Do not casually change this later; major upgrades require migration.
    package = pkgs.postgresql_16;

    # Database
    ensureDatabases = [
      "villy"
    ];

    ensureUsers = [
      {
        name = "villy";
        ensureDBOwnership = true;
      }
    ];

    # Network
    enableTCPIP = true;
    settings = {
      listen_addresses = lib.mkForce "127.0.0.1";

      # Connections
      max_connections = 100;

      # Memory
      shared_buffers = "2GB";
      effective_cache_size = "8GB";
      maintenance_work_mem = "512MB";
      work_mem = "16MB";

      # WAL / Checkpoints
      wal_buffers = "16MB";
      checkpoint_completion_target = 0.9;
      checkpoint_timeout = "15min";
      min_wal_size = "1GB";
      max_wal_size = "4GB";

      # Query planner
      random_page_cost = "1.1";
      effective_io_concurrency = 200;

      # Durability
      fsync = true;
      synchronous_commit = true;

      # Logging
      log_min_duration_statement = 1000;
      log_line_prefix = "%m [%p] %q%u@%d ";
      log_connections = true;
      log_disconnections = true;
      log_lock_waits = true;
    };

    # Authentication
    authentication = pkgs.lib.mkOverride 10 ''
      # TYPE  DATABASE        USER            ADDRESS                 METHOD

      # PostgreSQL administration through the local Unix socket.
      local   all             postgres                                peer

      # Application connections.
      local   all             all                                     scram-sha-256

      # Local TCP connections.
      host    all             all             127.0.0.1/32            scram-sha-256
      host    all             all             ::1/128                 scram-sha-256
    '';
  };

  # PostgreSQL backups
  services.postgresqlBackup = {
    enable = true;
    databases = [
      "villy"
    ];

    location = "/var/backup/postgresql";
    startAt = "*-*-* 02:00:00";
  };
}
