BIN := kubectl-netpol

.PHONY: build test lint clean install

build:
	go build -o $(BIN) .

test:
	go test ./...

lint:
	golangci-lint run ./...

clean:
	rm -f $(BIN)

install: build
	cp $(BIN) /usr/local/bin/$(BIN)
