# Home Media Server

## Plex
A closed source media stremaing server.

## Jellyfin
An open source media stremaing server.

## RClone
Backs up media to a ckoud storage provider via rclone.

## Traefik
Traefik is an open source edge router that allows the docker services to be made accessible via the web. It offers integration with cloudflare, where my domain is hosted, to generate SSL certificates. In this case, the configuration for traefik is built up via the labels on the respctive services.

## Cloudflare DDNS
Keeps the IP address that my base domain is pointint to in cloudflare up to date.

## Cloudflare Companion
Creates subdomain DNS entries for each of the services that are enable for traefik access.

## OAuth
Runs the OAuth server that provides access to the services made accessibly via traefik. This service requires OAuth setup on Google Cloud Platform.

## Portainer
Provides management utilities for the docker daemon via web GUI.

## Jackett
Provides indexers for Sonarr and Radarr, and Hydra.

## Radarr
Movie collection manager the integration with toerrent clients.

## Sonarr
TV show collection manager the integration with toerrent clients.

## Bazarr
Companion to Radarr and Sonarr whihc provides configurable subtitiles.

## Heimdall
Application dashboard.

## Socket Proxy
A security focused proxy for the docker socket.

## Hydra
Meta search for newznab indexers and torznab trackers.