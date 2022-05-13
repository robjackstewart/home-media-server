job "radarr" {
  datacenters = ["dc1"]
  type        = "service"

  update {
    max_parallel      = 1
    min_healthy_time  = "10s"
    healthy_deadline  = "3m"
    progress_deadline = "10m"
    auto_revert       = false
    canary            = 0
  }

  group "radarr" {
    count = 1

    network {
      port "http" {
        to = 7878
      }
    }

    restart {
      attempts = 2
      interval = "30s"
      delay    = "15s"
      mode     = "fail"
    }

    service {
        name = "radarr"
        port = "http"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.radarr.entrypoints=https",
          "traefik.http.routers.radarr.rule=Host(`radarr.$DOMAIN`)",
          "traefik.http.routers.radarr.middlewares=chain-oauth",
          "traefik.http.routers.radarr.service=radarr",
          "traefik.http.services.radarr.loadbalancer.server.port=7878"
        ]
        check {
          type     = "http"
          path     = "/"
          interval = "3s"
          timeout  = "20s"

          check_restart {
            limit = 3
            grace = "240s"
          }
        }
      }

    task "radarr" {
      driver = "docker"

      config {
        image = "linuxserver/radarr:latest"
        ports = ["http"]
        // volumes = [
        //   "/tmp/radarr/downloads:/downloads",
        //   "/tmp/radarr/appdata/radarr:/config",
        //   "/tmp/radarr/movies:/movies",
        //   "/tmp/radarr/shared:/shared"
        // ]
      }

      env {
        PUID = "1000"
        PGID = "1000"
        TZ   = "Europe/London"
      }

      // resources {
      //   memory = 512
      // }
    }
  }
}