# RCE webserver - Demo

this is designed and built to be a remote execution vulnerability, for security demonstrations.

** Under no circumstances should you run this except in a completely controlled test environment. **

- Listens on a port defined by the `--listen` flag (optional)
- Responds to GET requests on paths `/` with "hello world", and `/ping` with "pong"
- Responds to POST requests on path `/posts` and execute the command specified in the `cmd` query parameter if the `exploit` environment variable is set to "true"
- Makes HTTP requests to a list of hosts and ports every 30 seconds, specified by the `--connect` flag (optional)

## Usage
```
go run entrypoint.go --listen=:8080 --connect=example.com:80,google.com:80
```


### Flags

| Flag | Description |
|------|-------------|
| `--listen` | Port to listen on |
| `--connect` | List of hosts and ports to connect to |


### Endpoints

| Path | Method | Description |
|------|--------|-------------|
| `/` | GET | Responds with "hello world" |
| `/ping` | GET | Responds with "pong" |
| `/posts` | POST | Executes the command specified in the `cmd` query parameter if `exploit` environment variable is set to "true" |

## Example
```
$ go run entrypoint.go --listen=127.0.0.1:8080 --connect=example.com:80,google.com:80

2023/03/05 13:34:13 listening on :8080
2023/03/05 13:34:15 received GET request for /ping from 127.0.0.1:52230
2023/03/05 13:34:15 received GET request for /reply from 127.0.0.1:52230
2023/03/05 13:34:17 error resolving host example.com: lookup example.com: no such host
2023/03/05 13:34:17 error connecting to example.com (93.184.216.34): Get "http://example.com/": dial tcp 93.184.216.34:80: connect: connection refused
2023/03/05 13:34:17 response from google.com (172.217.166.174): 200 OK
2023/03/05 13:34:17 response from google.com (172.217.166.174): 200 OK
2023/03/05 13:34:17 response from google.com (172.217.166.174): 200 OK
2023/03/05 13:34:17 response from google.com (172.217.166.174): 200 OK
2023/03/05 13:34:17 response from google.com (172.217.166.174): 200 OK
2023/03/05 13:34:17 response from google.com (172.217.166.174): 200 OK
```

### RCE Demo

To activate the RCE, please set the exploit env variable to true

Make a POST request to `http://localhost:8080/posts` with the `cmd` argument set to `echo hello`:

```
$ export exploit=true
$ go run entrypoint.go --listen=127.0.0.1:8080 --connect=example.com:80,google.com:80
```

Open other terminal and run

```
$ curl -X POST -d "cmd=echo hello" http://localhost:8080/posts
```

### Simulates a Server Side Request Forgery (SSRF)

In this application, we will utilize it to replicate a Server Side Request Forgery (SSRF) scenario similar to the one mentioned in the Shopify bug bounty report. This particular SSRF vulnerability enabled an attacker to successfully obtain cloud credentials from the metadata server.

```
curl http://localhost:8080/fetch?url=http://checkip.dyndns.com

```

