.PHONY: run stop clean build push

run:
	docker-compose run --rm -p 8080:80 dev_pece

stop:
	docker-compose stop

clean:
	docker-compose down

build:
	docker-compose run --rm production /bin/bash

push:
	docker-compose run --rm production echo "Pushado! :)"
