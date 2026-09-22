.PHONY: test build run scan clean

IMAGE_NAME ?= assessment-api
IMAGE_TAG ?= local

test:
	go test -race ./...

build:
	docker build --build-arg VERSION=$(IMAGE_TAG) -t $(IMAGE_NAME):$(IMAGE_TAG) .

run:
	docker run --rm -p 8080:8080 $(IMAGE_NAME):$(IMAGE_TAG)

scan:
	trivy image --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed $(IMAGE_NAME):$(IMAGE_TAG)

clean:
	docker image rm $(IMAGE_NAME):$(IMAGE_TAG)

