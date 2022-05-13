job "sonarr" {
  datacenters = ["dc1"]
  type = "service"

  group "sonarr" {
    count = 1

    network {
      port "http" {
        to = 8989
      }
    }

    restart {
      attempts = 2
      interval = "30s"
      delay = "15s"
      mode = "fail"
    }

    task "sonarr" {
      driver = "docker"

      config {
        image = "linuxserver/sonarr:latest"
        ports =  ["http"]
        // volumes = [
        //   "/tmp/radarr/downloads:/downloads",
        //   "/tmp/radarr/appdata/radarr:/config",
        //   "/tmp/radarr/movies:/movies",
        //   "/tmp/radarr/shared:/shared"
        // ]
      }

      env {
        PUID  = "1000"
        PGID  = "1000"
        TZ    = "Europe/London"
      }

      // resources {
      //   memory = 512
      // }
    }
  }
}